#!/usr/bin/env python
import sys
import dxpy
import argparse
import subprocess
import time
import os
import json
import hashlib

argparser = argparse.ArgumentParser(description="Build the viral-ngs assembly workflow on DNAnexus.")
argparser.add_argument("--project", help="DNAnexus project ID", default="project-BXBXK180x0z7x5kxq11p886f")
argparser.add_argument("--folder", help="Folder within project (default: timestamp-based)", default=None)
argparser.add_argument("--no-applets", help="Assume applets already exist under designated folder", action="store_true")
argparser.add_argument("--contaminants", help="contaminants & adapters FASTA (default: %(default)s)",
                                         default="file-BXF0vYQ0QyBF509G9J12g927")
argparser.add_argument("--novocraft", help="Novocraft tarball (default: %(default)s)",
                                      default="file-BXJvFq00QyBKgFj9PZBqgbXg")
argparser.add_argument("--gatk", help="GATK tarball (default: %(default)s)",
                                 default="file-BXK8p100QyB0JVff3j9Y1Bf5")
argparser.add_argument("--run-tests", help="run small test assemblies", action="store_true")
argparser.add_argument("--run-large-tests", help="run test assemblies of varying sizes", action="store_true")
group = argparser.add_argument_group("filter")
group.add_argument("--filter-targets", help="panel of target sequences (default: %(default)s)",
                                default="file-BXF0vf80QyBF509G9J12g9F2")
group = argparser.add_argument_group("scaffold")
group.add_argument("--scaffold-reference", help="Reference genome FASTA (default: %(default)s)",
                                            default="file-BXF0vZ00QyBF509G9J12g944")
args = argparser.parse_args()

# detect git revision
here = os.path.dirname(sys.argv[0])
git_revision = subprocess.check_output(["git", "describe", "--always", "--dirty", "--tags"]).strip()

if args.folder is None:
    args.folder = time.strftime("/%Y-%m/%d-%H%M%S-") + git_revision

project = dxpy.DXProject(args.project)
applets_folder = args.folder + "/applets"
print "project: {} ({})".format(project.name, args.project)
print "folder: {}".format(args.folder)

def build_applets():
    applets = ["viral-ngs-human-depletion", "viral-ngs-filter", "viral-ngs-trinity", "viral-ngs-assembly-scaffolding", "viral-ngs-assembly-refinement", "viral-ngs-assembly-analysis"]

    project.new_folder(applets_folder, parents=True)
    for applet in applets:
        # TODO: reuse an existing applet with matching git_revision
        print "building {}...".format(applet),
        sys.stdout.flush()
        applet_dxid = json.loads(subprocess.check_output(["dx","build","--destination",args.project+":"+applets_folder+"/",os.path.join(here,applet)]))["id"]
        print applet_dxid
        applet = dxpy.DXApplet(applet_dxid, project=project.get_id())
        applet.set_properties({"git_revision": git_revision})

# helpers for name resolution
def find_app(app_handle):
    return dxpy.find_one_app(name=app_handle, zero_ok=False, more_ok=False, return_handler=True)

def find_applet(applet_name):
    return dxpy.find_one_data_object(classname='applet', name=applet_name,
                                     project=project.get_id(), folder=applets_folder,
                                     zero_ok=False, more_ok=False, return_handler=True)

def build_workflow():
    wf = dxpy.new_dxworkflow(title='viral-ngs-assembly',
                              name='viral-ngs-assembly',
                              description='viral-ngs-assembly',
                              project=args.project,
                              folder=args.folder,
                              properties={"git_revision": git_revision})
    
    depletion_input = {}
    depletion_stage_id = wf.add_stage(find_applet("viral-ngs-human-depletion"), stage_input=depletion_input, name="deplete", folder="intermediates")

    filter_input = {
        "reads": dxpy.dxlink({"stage": depletion_stage_id, "outputField": "unmapped_bam"}),
        "min_base_count": 500000,
        "targets": dxpy.dxlink(args.filter_targets),
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    filter_stage_id = wf.add_stage(find_applet("viral-ngs-filter"), stage_input=filter_input, name="filter", folder="intermediates")

    trinity_input = {
        "reads": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads"}),
        "contaminants": dxpy.dxlink(args.contaminants),
        "subsample": 100000,
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    trinity_stage_id = wf.add_stage(find_applet("viral-ngs-trinity"), stage_input=trinity_input, name="trinity", folder="intermediates")

    scaffold_input = {
        "trinity_contigs": dxpy.dxlink({"stage": trinity_stage_id, "outputField": "contigs"}),
        "trinity_reads": dxpy.dxlink({"stage": trinity_stage_id, "inputField": "reads"}),
        "reference_genome" : dxpy.dxlink(args.scaffold_reference),
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    scaffold_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-scaffolding"), stage_input=scaffold_input, name="scaffold", folder="intermediates")

    refine1_input = {
        "assembly": dxpy.dxlink({"stage": scaffold_stage_id, "outputField": "modified_scaffold"}),
        "reads": dxpy.dxlink({"stage": depletion_stage_id, "outputField": "unmapped_bam"}),
        "min_coverage": 2,
        "novoalign_options": "-r Random -l 30 -g 40 -x 20 -t 502",
        "novocraft_tarball": dxpy.dxlink({"stage": scaffold_stage_id, "inputField": "novocraft_tarball"}),
        "gatk_tarball": dxpy.dxlink({"stage": scaffold_stage_id, "inputField": "gatk_tarball"}),
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    refine1_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-refinement"), stage_input=refine1_input, name="refine1", folder="intermediates")

    refine2_input = refine1_input
    refine2_input["assembly"] = dxpy.dxlink({"stage": refine1_stage_id, "outputField": "refined_assembly"})
    refine2_input["min_coverage"] = 3
    refine2_input["novoalign_options"] = "-r Random -l 40 -g 40 -x 20 -t 100"
    refine2_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-refinement"), stage_input=refine2_input, name="refine2", folder="intermediates")

    analysis_input = {
        "assembly": dxpy.dxlink({"stage": refine2_stage_id, "outputField": "refined_assembly"}),
        "reads": dxpy.dxlink({"stage": refine2_stage_id, "inputField": "reads"}),
        "novoalign_options": "-r Random -l 40 -g 40 -x 20 -t 100 -k -c 3",
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"}),
        "novocraft_tarball": dxpy.dxlink({"stage": scaffold_stage_id, "inputField": "novocraft_tarball"}),
        "gatk_tarball": dxpy.dxlink({"stage": scaffold_stage_id, "inputField": "gatk_tarball"})
    }
    analysis_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-analysis"), stage_input=analysis_input, name="analysis")

    # TODO populate workflow README
    return wf

# main
if args.no_applets is not True:
    build_applets()

workflow = build_workflow()

if args.run_tests is True or args.run_large_tests is True:
    muscle_applet = dxpy.DXApplet("applet-BXQxjv00QyB9QF3vP4BpXg95")

    # test data found in "bi-viral-ngs CI:/test_data"
    test_samples = {
        "SRR1553416": {
            "reads": "file-BXBP0VQ011y0B0g5bbJFzx51",
            "reads2": "file-BXBP0Xj011yFYvPjgJJ0GzZB",
            "broad_assembly": "file-BXFqQvQ0QyB5859Vpx1j7bqq",
            "expected_assembly_sha256sum": "411834d66c5226651493b9b921a157984db030a3a5d048975b709806228d3806",
            "expected_subsampled_base_count": 459632,
            "expected_alignment_base_count": 485406
        },
        "SRR1553554": {
            "reads": "file-BXPPQ2Q0YzB28x9Q9911Ykz5",
            "reads2": "file-BXPPQ380YzB6xGxJ45K9Yv6Q",
            "broad_assembly": "file-BXQx6G00QyB6PQVYKQBgzxv4",
            "expected_assembly_sha256sum": "af4328b04113a149e66055c113ef35fa566e691a2eabde85231ccf2a08df1bf4",
            "expected_subsampled_base_count":  467842,
            "expected_alignment_base_count": 590547
        }
    }

    if args.run_large_tests is True:
        # nb this sample takes too long for Travis
        test_samples["SRR1553468"] = {
            "reads": "file-BXYqZj80Fv4YqP151Zy9291y",
            "reads2": "file-BXYqZkQ0Fv4YZYKx14yJg0b4",
            "broad_assembly": "file-BXYqYKQ0QyB84xYJP9Kz7zzK",
            "expected_assembly_sha256sum": "456bd7e050222e0eff4fbe4a04c4124695c89d0533b318a49777789f3ed8bb2b",
            "expected_subsampled_base_count": 18787806,
            "expected_alignment_base_count": 247110236
        }

    test_analyses = []
    for test_sample in test_samples.keys():
        # create a subfolder for this sample
        test_folder = args.folder + "/" + test_sample
        project.new_folder(test_folder)
        # run the workflow on the test sample
        test_input = {
            "deplete.file": dxpy.dxlink(test_samples[test_sample]["reads"]),
            "deplete.paired_fastq": dxpy.dxlink(test_samples[test_sample]["reads2"]),
            "deplete.skip_depletion": True,
            "scaffold.novocraft_tarball": dxpy.dxlink(args.novocraft),
            "scaffold.gatk_tarball": dxpy.dxlink(args.gatk),
        }
        test_analysis = workflow.run(test_input, project=project.get_id(), folder=test_folder, name=(git_revision+" "+test_sample), priority="normal")
        print "Launched {} for {}".format(test_analysis.get_id(), test_sample)
        test_analyses.append((test_sample,test_analysis))

    # wait for jobs to finish while working around Travis 10m console inactivity timeout
    print "Waiting for analyses to finish..."
    noise = subprocess.Popen(["/bin/bash", "-c", "while true; do date; sleep 60; done"])
    try:
        for (test_sample,test_analysis) in test_analyses:
            test_analysis.wait_on_done()

            # for diagnostics: add on a MUSCLE alignment of the Broad's
            # assembly of the sample with the workflow products
            muscle_input = {
                "fasta": [
                    test_analysis.get_output_ref(workflow.get_stage("scaffold")["id"]+".vfat_scaffold"),
                    test_analysis.get_output_ref(workflow.get_stage("scaffold")["id"]+".modified_scaffold"),
                    test_analysis.get_output_ref(workflow.get_stage("refine1")["id"]+".refined_assembly"),
                    test_analysis.get_output_ref(workflow.get_stage("refine2")["id"]+".refined_assembly"),
                    dxpy.dxlink(test_samples[test_sample]["broad_assembly"])
                ],
                "output_format": "html",
                "output_name": test_sample+"_test_alignment",
                "advanced_options": "-maxiters 2"
            }
            muscle_applet.run(muscle_input, project=project.get_id(), folder=(args.folder+"/"+test_sample), name=(git_revision+" "+test_sample+" MUSCLE"), instance_type="mem1_ssd1_x4")
    finally:
        noise.kill()

    # check figures of merit
    for (test_sample,test_analysis) in test_analyses:
        subsampled_base_count = test_analysis.describe()["output"][workflow.get_stage("trinity")["id"]+".subsampled_base_count"]
        expected_subsampled_base_count = test_samples[test_sample]["expected_subsampled_base_count"]
        print "\t".join([test_sample, "subsampled_base_count", str(expected_subsampled_base_count), str(subsampled_base_count)])

        test_assembly_dxfile = dxpy.DXFile(test_analysis.describe()["output"][workflow.get_stage("analysis")["id"]+".final_assembly"])
        test_assembly_sha256sum = hashlib.sha256(test_assembly_dxfile.read()).hexdigest()
        expected_sha256sum = test_samples[test_sample]["expected_assembly_sha256sum"]
        print "\t".join([test_sample, "sha256sum", expected_sha256sum, test_assembly_sha256sum])

        alignment_base_count = test_analysis.describe()["output"][workflow.get_stage("analysis")["id"]+".alignment_base_count"]
        expected_alignment_base_count = test_samples[test_sample]["expected_alignment_base_count"]
        print "\t".join([test_sample, "alignment_base_count", str(expected_alignment_base_count), str(alignment_base_count)])
        
        assert expected_sha256sum == test_assembly_sha256sum
        assert expected_subsampled_base_count == subsampled_base_count
        assert expected_alignment_base_count == alignment_base_count

    print "Success"
