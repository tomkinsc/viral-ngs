#!/usr/bin/env/python
import sys
import dxpy
import argparse
import subprocess
import time
import os

argparser = argparse.ArgumentParser(description="Build the viral-ngs assembly workflow on DNAnexus.")
argparser.add_argument("--project", help="DNAnexus project ID", default="project-BXBXK180x0z7x5kxq11p886f")
argparser.add_argument("--folder", help="Folder within project (default: timestamp-based)", default=None)
argparser.add_argument("--no-applets", help="Assume applets already exist under designated folder", action="store_true")
argparser.add_argument("--resources", help="viral-ngs resources tarball (default: %(default)s)",
                                      default="file-BXFjVfQ0gZG8GfpV91XvxKKF")
argparser.add_argument("--SRR1553416", help="launch assembly of SRR1553416", action="store_true")
group = argparser.add_argument_group("trim")
group.add_argument("--trim-contaminants", help="adapters & contaminants FASTA (default: %(default)s)",
                                     default="file-BXF0vYQ0QyBF509G9J12g927")
group = argparser.add_argument_group("filter")
group.add_argument("--filter-targets", help="panel of target sequences (default: %(default)s)",
                                default="file-BXF0vf80QyBF509G9J12g9F2")
group = argparser.add_argument_group("trinity")
group.add_argument("--trinity-applet", help="Trinity wrapper applet (default: %(default)s)",
                                       default="applet-BX6Zjz00QyB8PyY514B9pY1k")
group = argparser.add_argument_group("finishing")
group.add_argument("--finishing-reference", help="Reference genome FASTA (default: %(default)s)",
                                            default="file-BXF0vZ00QyBF509G9J12g944")

args = argparser.parse_args()

if args.folder is None:
    args.folder = time.strftime("/%Y-%m-%d/%H%M%S") # TODO add commit hash subfolder

project = dxpy.DXProject(args.project)
applets_folder = args.folder + "/applets"
print "project: {} ({})".format(project.name, args.project)
print "folder: {}".format(args.folder)

def build_applets():
    applets = ["viral-ngs-trimmer", "viral-ngs-filter-lastal", "viral-ngs-assembly-finisher"]
    here = os.path.dirname(sys.argv[0])

    project.new_folder(applets_folder, parents=True)
    for applet in applets:
        print "building {}...".format(applet),
        sys.stdout.flush()
        subprocess.check_call(["dx","build","--destination",args.project+":"+applets_folder+"/",os.path.join(here,applet)])

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
                              folder=args.folder)
    
    trim_input = {
        "adapters_etc": dxpy.dxlink(args.trim_contaminants),
        "resources": dxpy.dxlink(args.resources)
    }
    trim_stage_id = wf.add_stage(find_applet("viral-ngs-trimmer"), stage_input=trim_input, name="trim")

    filter_input = {
        "reads": dxpy.dxlink({"stage": trim_stage_id, "outputField": "trimmed_reads"}),
        "reads2": dxpy.dxlink({"stage": trim_stage_id, "outputField": "trimmed_reads2"}),
        "reference": dxpy.dxlink(args.filter_targets), # TODO rename 'reference' input
        "resources": dxpy.dxlink({"stage": trim_stage_id, "inputField": "resources"})
    }
    filter_stage_id = wf.add_stage(find_applet("viral-ngs-filter-lastal"), stage_input=filter_input, name="filter")

    trinity_input = {
        "reads": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads"}),
        "reads2": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads2"}),
        "advanced_options": "--min_contig_length 300"
    }
    trinity_stage_id = wf.add_stage(args.trinity_applet, stage_input=trinity_input, name="trinity")

    finishing_input = {
        "raw_assembly": dxpy.dxlink({"stage": trinity_stage_id, "outputField": "fasta"}),
        "reads": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads"}),
        "reads2": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads2"}),
        "reference_genome" : dxpy.dxlink(args.finishing_reference),
        "resources": dxpy.dxlink({"stage": trim_stage_id, "inputField": "resources"})
    }
    finishing_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-finisher"), stage_input=finishing_input, name="finishing")

    # TODO populate workflow README
    # TODO set property on workflow with git revision
    return wf

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
    # TODO: wait on done?
