#!/usr/bin/env python
import sys
import dxpy
import argparse
import subprocess
import time
import os
import json

argparser = argparse.ArgumentParser(description="Build the viral-ngs assembly workflow on DNAnexus.")
argparser.add_argument("--project", help="DNAnexus project ID", default="project-BXBXK180x0z7x5kxq11p886f")
argparser.add_argument("--folder", help="Folder within project (default: timestamp-based)", default=None)
argparser.add_argument("--no-applets", help="Assume applets already exist under designated folder", action="store_true")
argparser.add_argument("--resources", help="viral-ngs resources tarball (default: %(default)s)",
                                      default="file-BXJk07j0zX142V4kf1JGF991")
argparser.add_argument("--run-tests", help="run test assemblies", action="store_true")
group = argparser.add_argument_group("trim")
group.add_argument("--trim-contaminants", help="adapters & contaminants FASTA (default: %(default)s)",
                                     default="file-BXF0vYQ0QyBF509G9J12g927")
group = argparser.add_argument_group("filter")
group.add_argument("--filter-targets", help="panel of target sequences (default: %(default)s)",
                                default="file-BXF0vf80QyBF509G9J12g9F2")
group = argparser.add_argument_group("trinity")
group.add_argument("--trinity-applet", help="Trinity wrapper applet (default: %(default)s)",
                                       default="applet-BXJ6F5Q0QyB7gy2Gf1p8jqfF")
group = argparser.add_argument_group("scaffold")
group.add_argument("--scaffold-reference", help="Reference genome FASTA (default: %(default)s)",
                                            default="file-BXF0vZ00QyBF509G9J12g944")
group = argparser.add_argument_group("refine")
group.add_argument("--refine-novocraft", help="Novocraft tarball (default: %(default)s)",
                                         default="file-BXJvFq00QyBKgFj9PZBqgbXg")
group.add_argument("--refine-gatk", help="GATK tarball (default: %(default)s)",
                                    default="file-BXK8p100QyB0JVff3j9Y1Bf5")
group.add_argument("--refine-debug", help="Import refinement intermediates for visualization",
                                     action="store_true")
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
    applets = ["viral-ngs-trimmer", "viral-ngs-filter-lastal", "viral-ngs-assembly-scaffolding", "viral-ngs-assembly-refinement"]

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
    
    trim_input = {
        "adapters_etc": dxpy.dxlink(args.trim_contaminants),
        "resources": dxpy.dxlink(args.resources)
    }
    trim_stage_id = wf.add_stage(find_applet("viral-ngs-trimmer"), stage_input=trim_input, name="trim")

    filter_input = {
        "reads": dxpy.dxlink({"stage": trim_stage_id, "outputField": "trimmed_reads"}),
        "reads2": dxpy.dxlink({"stage": trim_stage_id, "outputField": "trimmed_reads2"}),
        "targets": dxpy.dxlink(args.filter_targets),
        "resources": dxpy.dxlink({"stage": trim_stage_id, "inputField": "resources"})
    }
    filter_stage_id = wf.add_stage(find_applet("viral-ngs-filter-lastal"), stage_input=filter_input, name="filter")

    trinity_input = {
        "reads": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads"}),
        "reads2": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads2"}),
        "advanced_options": "--min_contig_length 300"
    }
    trinity_stage_id = wf.add_stage(args.trinity_applet, stage_input=trinity_input, name="trinity", instance_type="mem2_ssd1_x2")

    scaffold_input = {
        "trinity_contigs": dxpy.dxlink({"stage": trinity_stage_id, "outputField": "fasta"}),
        "trinity_reads": dxpy.dxlink({"stage": trinity_stage_id, "inputField": "reads"}),
        "trinity_reads2": dxpy.dxlink({"stage": trinity_stage_id, "inputField": "reads2"}),
        "reference_genome" : dxpy.dxlink(args.scaffold_reference),
        "resources": dxpy.dxlink({"stage": trim_stage_id, "inputField": "resources"})
    }
    scaffold_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-scaffolding"), stage_input=scaffold_input, name="scaffold")

    refine1_input = {
        "assembly": dxpy.dxlink({"stage": scaffold_stage_id, "outputField": "modified_scaffold"}),
        "reads": dxpy.dxlink({"stage": trim_stage_id, "inputField": "reads"}),
        "reads2": dxpy.dxlink({"stage": trim_stage_id, "inputField": "reads2"}),
        "min_coverage": 1,
        "novoalign_options": "-r Random -l 30 -g 40 -x 20 -t 502",
        "resources": dxpy.dxlink({"stage": trim_stage_id, "inputField": "resources"}),
        "novocraft_tarball": dxpy.dxlink(args.refine_novocraft),
        "gatk_tarball": dxpy.dxlink(args.refine_gatk)
    }
    refine1_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-refinement"), stage_input=refine1_input, name="refine1")

    refine2_input = refine1_input
    refine2_input["assembly"] = dxpy.dxlink({"stage": refine1_stage_id, "outputField": "refined_assembly"})
    refine2_input["min_coverage"] = 3
    refine2_input["novoalign_options"] = "-r Random -l 40 -g 40 -x 20 -t 100"
    refine2_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-refinement"), stage_input=refine2_input, name="refine2")

    """
    if args.refine_debug is True:
        refine1_genome_importer_input = {
            "file": dxpy.dxlink({"stage": refine1_stage_id, "outputField": "refined_assembly"})
        }
        genome_importer_stage_id = wf.add_stage(find_app("fasta_contigset_importer"), stage_input=genome_importer_input, name="import_genome", instance_type="mem2_ssd1_x2")

        mappings_importer_input = {
            "file": 
        }
    """

    # TODO: map reads against assembly
    # TODO: optionally import assembly & mappings for visualization.
    """
    genome_importer_input = {
        "file": dxpy.dxlink({"stage": last_stage_id, "outputField": "refined_assembly"})
    }
    genome_importer_stage_id = wf.add_stage(find_app("fasta_contigset_importer"), stage_input=genome_importer_input, name="import_genome", instance_type="mem2_ssd1_x2")

    mappings_importer_input = {
        "file": 
    }
    """

    # TODO populate workflow README
    return wf

# main
if args.no_applets is not True:
    build_applets()

workflow = build_workflow()

if args.run_tests is True:
    muscle_applet = dxpy.DXApplet("applet-BXQxjv00QyB9QF3vP4BpXg95")

    # test data found in "bi-viral-ngs CI:/test_data"
    test_samples = {
        "SRR1553416": {
            "reads": "file-BXBP0VQ011y0B0g5bbJFzx51",
            "reads2": "file-BXBP0Xj011yFYvPjgJJ0GzZB",
            "broad_assembly": "file-BXFqQvQ0QyB5859Vpx1j7bqq"
        },
        "SRR1553554": {
            "reads": "file-BXPPQ2Q0YzB28x9Q9911Ykz5",
            "reads2": "file-BXPPQ380YzB6xGxJ45K9Yv6Q",
            "broad_assembly": "file-BXQx6G00QyB6PQVYKQBgzxv4"
        }
    }

    jobs = []
    for test_sample in test_samples.keys():
        # create a subfolder for this sample
        test_folder = args.folder + "/" + test_sample
        project.new_folder(test_folder)
        # run the workflow on the test sample
        test_input = {
            "trim.reads": dxpy.dxlink(test_samples[test_sample]["reads"]),
            "trim.reads2": dxpy.dxlink(test_samples[test_sample]["reads2"]),
            "filter.read_id_regex": "^@(\\S+).[1|2] .*"
        }
        test_analysis = workflow.run(test_input, project=project.get_id(), folder=test_folder, name=(git_revision+" "+test_sample))
        print "Launched {} for {}".format(test_analysis.get_id(), test_sample)
        # add on a MUSCLE alignment of the Broad's assembly of the sample with
        # intermediate and final products of the workflow
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
        jobs.append(muscle_applet.run(muscle_input, project=project.get_id(), folder=test_folder, name=(git_revision+" "+test_sample+" MUSCLE"), instance_type="mem2_ssd1_x2"))

    # wait for jobs to finish while working around Travis 10m console inactivity timeout
    print "Waiting for jobs to finish..."
    noise = subprocess.Popen(["/bin/bash", "-c", "while true; do date; sleep 60; done"])
    try:
        for job in jobs:
            job.wait_on_done()
    finally:
        noise.kill()
    print "Success"
