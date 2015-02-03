#!/usr/bin/env python

import sys
import dxpy
import argparse
import time
import subprocess
import tempfile
import os
from Bio import SeqIO

parser = argparse.ArgumentParser(description="viral-ngs-assembly DNAnexus workflow validation")
subparsers = parser.add_subparsers()

def launch(args):
    run_id = generate_run_id()
    args.folder = args.folder or ("/validation/"+run_id)
    project = dxpy.DXProject(args.project)
    workflow = dxpy.DXWorkflow(args.workflow)
    muscle_applet = dxpy.DXApplet(args.muscle)

    # find input BAMs from the 'EBOV validation data' project
    bi_project = "project-BXz7QkQ0K7jf8bQ74GzG9gvY"
    input_bam_ext = ".cleaned.bam"
    fdo = dxpy.search.find_data_objects
    bi_input_bams = list(fdo(project=bi_project, folder="/data/01_per_sample", classname="file",
                             name=("*"+input_bam_ext), name_mode="glob", return_handler=True))
    bi_input_bams = dict([(strip_end(b.name, input_bam_ext), b) for b in bi_input_bams])
    print("Found {} input BAMs".format(len(bi_input_bams)))

    # find output assemblies from the 'EBOV validation data' project
    bi_assemblies = list(fdo(project=bi_project, folder="/data/02_assembly", classname="file",
                             name="*.fasta", name_mode="glob", return_handler=True))
    bi_assemblies = dict([(strip_end(f.name, ".fasta"), f) for f in bi_assemblies])
    print("Found {} output assemblies".format(len(bi_assemblies)))

    run_details = {"id": run_id, "workflow": args.workflow, "samples": {}}

    # join them
    sample_count = 0
    for sample, bi_assembly in bi_assemblies.iteritems():
        try:
            bam = bi_input_bams[sample]
        except:
            raise KeyError("Couldn't find input BAM for " + sample)
        run_details["samples"][sample] = {
            "bi_assembly": bi_assembly.get_id(),
            "input_bam": bam.get_id()
        }
        sample_count = sample_count+1
        if args.limit and sample_count >= args.limit:
            break

    print("{} launching {} samples".format(run_id,sample_count))
    project.new_folder(args.folder, parents=True)
    run_record = dxpy.new_dxrecord(project=args.project, folder=args.folder, name=run_id)

    # Launch workflow on each sample
    for sample, sample_details in run_details["samples"].iteritems():
        analysis_input = {
            "validate.file": dxpy.dxlink(sample_details["input_bam"]),
            "validate.novocraft_tarball": dxpy.dxlink(args.novocraft),
            "validate.gatk_tarball": dxpy.dxlink(args.gatk)
        }
        analysis_folder = args.folder + "/" + sample
        project.new_folder(analysis_folder, parents=True)
        analysis = workflow.run(analysis_input, project=project.get_id(), folder=analysis_folder,
                                name=("viral-ngs-assembly validation " + run_id + " "  + sample),
                                priority="normal")
        sample_details["analysis"] = analysis.get_id()
        print("{} {}".format(analysis.get_id(),analysis.name))

        # also schedule MUSCLE alignment of final assemblies
        muscle_input = {
            "fasta": [
                dxpy.dxlink(sample_details["bi_assembly"]),
                analysis.get_output_ref(workflow.get_stage("analysis")["id"]+".final_assembly")
            ],
            "output_format": "fasta",
            "output_name": sample+"_validation_alignment",
            "advanced_options": "-maxiters 2"
        }
        muscle_job = muscle_applet.run(muscle_input, project=project.get_id(), folder=analysis_folder,
                                       name=("viral-ngs-assembly validation " + run_id + " "  + sample + " MUSCLE"),
                                       instance_type="mem1_ssd1_x4", priority="normal")
        sample_details["muscle"] = muscle_job.get_id()
        print("{} {}".format(muscle_job.get_id(),muscle_job.name))

    run_record.set_details(run_details)
    run_record.close()
    print("{} {}".format(run_id, run_record.get_id()))

parser_launch = subparsers.add_parser("launch")
parser_launch.set_defaults(func=launch)
parser_launch.add_argument("workflow", help="viral-ngs-assembly workflow ID (required)")
parser_launch.add_argument("--project", help="DNAnexus project ID (default: %(default)s)",
                                        default="project-BX6FjJ00QyB3X12J59PVYZ1V")
parser_launch.add_argument("--folder", help="Folder within project (default: timestamp-based)", default=None)
parser_launch.add_argument("--novocraft", help="Novocraft tarball (default: %(default)s)",
                                          default="file-BXJvFq00QyBKgFj9PZBqgbXg")
parser_launch.add_argument("--gatk", help="GATK tarball (default: %(default)s)",
                                     default="file-BXK8p100QyB0JVff3j9Y1Bf5")
parser_launch.add_argument("--muscle", help="Muscle applet ID (default: %(default)s)",
                                       default="applet-BXQxjv00QyB9QF3vP4BpXg95")
parser_launch.add_argument("--limit", metavar="N", type=int, default=None,
                                      help="Launch workflow on no more than this many samples")


def postmortem(args):
    record = dxpy.DXRecord(dxpy.dxlink(args.record, args.project))
    run_details = record.get_details()

    finished = {}

    # check for analysis completion
    for sample, sample_details in run_details["samples"].iteritems():
        analysis = dxpy.DXAnalysis(sample_details["analysis"])
        analysis_desc = analysis.describe()
        analysis_state = analysis_desc["state"]

        if analysis_state == "in_progress":
            print("\t".join(["analysis_in_progress", sample, analysis.get_id(), analysis_state]))
        elif analysis_state != "done":
            print("\t".join(["analysis_failed", sample, analysis.get_id(), analysis_state,
                             str(get_analysis_output(analysis_desc, ".filtered_base_count")),
                             str(get_analysis_output(analysis_desc, ".subsampled_base_count"))]))
        else:
            muscle_job = dxpy.DXJob(sample_details["muscle"])
            muscle_job_state = muscle_job.describe()["state"]
            if muscle_job_state in ["idle", "waiting_on_input", "runnable", "running", "waiting_on_output"]:
                print("\t".join(["muscle_in_progress", sample, muscle_job.get_id(), muscle_job_state]))
            elif muscle_job_state != "done":
                print("\t".join(["muscle_failed", sample, muscle_job.get_id(), muscle_job_state]))
            else:
                finished[sample] = (analysis,muscle_job)

    # compare the completed assemblies
    for sample, (analysis, muscle_job) in finished.iteritems():
        muscle_fasta = dxpy.DXFile(muscle_job.describe()["output"]["alignment"])
        handle, local_fasta = tempfile.mkstemp(".fasta")
        os.close(handle)
        dxpy.download_dxfile(muscle_fasta.get_id(), local_fasta)
        L, identical, N, gap, other = muscle_consensus_identity(local_fasta)
        os.unlink(local_fasta)

        analysis_desc = analysis.describe()
        print("\t".join(["validation_result", sample,
                         str(get_analysis_output(analysis_desc, ".filtered_base_count")),
                         str(get_analysis_output(analysis_desc, ".subsampled_base_count")),
                         str(get_analysis_output(analysis_desc, ".mean_coverage_depth")),
                         str(L), str(identical), "{:.2f}".format(100.0*identical/L),
                         str(N), str(gap), str(other), str(analysis_desc["totalPrice"])]))

    # TODO: compare mapped BAMs?

parser_postmortem = subparsers.add_parser("postmortem")
parser_postmortem.set_defaults(func=postmortem)
parser_postmortem.add_argument("record", help="ID of the run record created at launch (required)")
parser_postmortem.add_argument("--project", help="DNAnexus project ID (default: %(default)s)",
                                            default="project-BX6FjJ00QyB3X12J59PVYZ1V")

def generate_run_id():
    # detect git revision
    here = os.path.dirname(sys.argv[0]) or "."
    git_revision = subprocess.check_output(["git", "-C", here, "describe", "--always", "--dirty", "--tags"]).strip()
    return time.strftime("%Y-%m-%d-%H%M%S-") + git_revision

def get_analysis_output(desc, output_name):
    if "output" in desc:
        for k, v in desc["output"].iteritems():
            if k.endswith(output_name):
                return v
    return None

def muscle_consensus_identity(fasta):
    seqs = []
    with open(fasta, "rU") as infile:
        for record in SeqIO.parse(infile, "fasta") :
            seqs.append(record.seq.upper())
    assert (len(seqs) == 2)
    assert (len(seqs[0]) == len(seqs[1]))
    L = len(seqs[0])
    identical = 0
    N = 0
    gap = 0
    other = 0
    for i in xrange(L):
        if seqs[0][i] == seqs[1][i]:
            identical = identical + 1
        elif seqs[0][i] == "N" or seqs[1][i] == "N":
            N = N + 1
        elif seqs[0][i] == "-" or seqs[1][i] == "-":
            gap = gap + 1
        else:
            other = other + 1
    return (L,identical,N,gap,other)

def strip_end(text, suffix):
    if not text.endswith(suffix):
        return text
    return text[:len(text)-len(suffix)]

if __name__ == "__main__":
    args = parser.parse_args()
    args.func(args)


