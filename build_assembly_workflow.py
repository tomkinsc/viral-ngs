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
argparser.add_argument("--SRR1553416", help="run assembly of SRR1553416", action="store_true")
group = argparser.add_argument_group("trim")
group.add_argument("--trim-contaminants", help="adapters & contaminants FASTA (default: %(default)s)",
                                     default="file-BXF0vYQ0QyBF509G9J12g927")
group = argparser.add_argument_group("filter")
group.add_argument("--filter-targets", help="panel of target sequences (default: %(default)s)",
                                default="file-BXF0vf80QyBF509G9J12g9F2")
group = argparser.add_argument_group("trinity")
group.add_argument("--trinity-applet", help="Trinity wrapper applet (default: %(default)s)",
                                       default="applet-BXJ6F5Q0QyB7gy2Gf1p8jqfF")
group = argparser.add_argument_group("finishing")
group.add_argument("--finishing-reference", help="Reference genome FASTA (default: %(default)s)",
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
    applets = ["viral-ngs-trimmer", "viral-ngs-filter-lastal", "viral-ngs-assembly-finisher"]

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

    finishing_input = {
        "trinity_assembly": dxpy.dxlink({"stage": trinity_stage_id, "outputField": "fasta"}),
        "reads": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads"}),
        "reads2": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads2"}),
        "reference_genome" : dxpy.dxlink(args.finishing_reference),
        "resources": dxpy.dxlink({"stage": trim_stage_id, "inputField": "resources"})
    }
    finishing_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-finisher"), stage_input=finishing_input, name="finishing")

    # TODO populate workflow README
    return wf

# main
if args.no_applets is not True:
    build_applets()

workflow = build_workflow()

if args.SRR1553416 is True:
    SRR1553416_folder = args.folder + "/SRR1553416"
    project.new_folder(SRR1553416_folder)
    SRR1553416_input = {
        "trim.reads": dxpy.dxlink("file-BXBP0VQ011y0B0g5bbJFzx51"),
        "trim.reads2": dxpy.dxlink("file-BXBP0Xj011yFYvPjgJJ0GzZB"),
        "filter.read_id_regex": "^@(\\S+).[1|2] .*"
    }
    analysis = workflow.run(SRR1553416_input, project=project.get_id(), folder=SRR1553416_folder)
    print "Launched {} on SRR1553416".format(analysis.get_id())
    # analysis.wait_on_done() # not used because of Travis' 10m console inactivity timeout
    while analysis.describe()["state"] == "in_progress":
        print analysis.describe()["output"]
        time.sleep(30)
    print analysis.describe()["output"]
