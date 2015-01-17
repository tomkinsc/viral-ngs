#!/usr/bin/env python
import sys
import dxpy
import argparse
import subprocess
import time
import os

argparser = argparse.ArgumentParser(description="Build the viral-ngs resources tarball on DNAnexus.")
argparser.add_argument("--novocraft", help="Novocraft tarball (default: %(default)s)",
                                      default="file-BXJvFq00QyBKgFj9PZBqgbXg")
argparser.add_argument("--gatk", help="GATK tarball (default: %(default)s)",
                                 default="file-BXK8p100QyB0JVff3j9Y1Bf5")
argparser.add_argument("--project", help="DNAnexus project ID", default="project-BXBXK180x0z7x5kxq11p886f")
argparser.add_argument("--folder", help="Folder within project (default: %(default)s)", default="/resources_tarball")
argparser.add_argument("--reuse-builder", help="Reuse the existing 'builder' applet instead of recreating it", action="store_true")
argparser.add_argument("gitref", help="dnanexus/viral-ngs git ref to build")
args = argparser.parse_args()

project = dxpy.DXProject(args.project)
print "project: {} ({})".format(project.name, args.project)
project.new_folder(args.folder, parents=True)
print "folder: {}".format(args.folder)

# TODO: memoization scheme?

if args.reuse_builder is not True:
	subprocess.check_call(["dx","build","-f","--destination",args.project+":"+args.folder+"/",
		                   os.path.join(os.path.dirname(sys.argv[0]),"viral-ngs-builder")])
            
builder = dxpy.find_one_data_object(classname='applet', name="viral-ngs-builder",
                                     project=args.project, folder=args.folder,
                                     zero_ok=False, more_ok=False, return_handler=True)

builder_input = {
	"git_commit": args.gitref,
	"novocraft_tarball": dxpy.dxlink(args.novocraft),
	"gatk_tarball": dxpy.dxlink(args.gatk)
}
job = builder.run(builder_input, project=args.project, folder=args.folder, name=("viral-ngs-bulder " + args.gitref))
print "builder job: {}".format(job.get_id())
job.wait_on_done()

id, _ = dxpy.get_dxlink_ids(job.describe()["output"]["resources"])
print id
