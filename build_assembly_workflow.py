#!/usr/bin/env python
import sys
import dxpy
import argparse
import subprocess
import time
import os
import json
import hashlib

species_resource = {
    'Ebola':{
        'contaminants': 'file-BXF0vYQ0QyBF509G9J12g927',
        'filter-targets': 'file-BXF0vf80QyBF509G9J12g9F2',
        'scaffold-reference': 'file-BXF0vZ00QyBF509G9J12g944'
    },
    'Lassa':{
        'contaminants': 'file-BXF0vYQ0QyBF509G9J12g927',
        'filter-targets': 'file-Bg533J00x0zBkYkFGb23k58B',
        'scaffold-reference': 'file-Bg533J00x0zBkYkFGb23k58B'
    },
    'Generic':{
        'contaminants': 'file-BXF0vYQ0QyBF509G9J12g927'
    }
}
valid_species = species_resource.keys()

argparser = argparse.ArgumentParser(description="Build the viral-ngs assembly workflow on DNAnexus.")
argparser.add_argument("--project", help="DNAnexus project ID", default="project-BXBXK180x0z7x5kxq11p886f")
argparser.add_argument("--folder", help="Folder within project (default: timestamp-based)", default=None)
argparser.add_argument("--species", help="Build workflow(s) by populating resources for the specified species. \
                                    Allows for multiple species to be chosen. 'Generic' builds a workflow without chaining species-specific resource. Choices: %(choices)s",
                                    nargs='+', choices=valid_species, default=["Generic"])
argparser.add_argument("--no-applets", help="Assume applets already exist under designated folder", action="store_true")
# argparser.add_argument("--contaminants", help="contaminants & adapters FASTA (default: %(default)s)",
#                                          default="file-BXF0vYQ0QyBF509G9J12g927")
argparser.add_argument("--novocraft", help="Novocraft tarball (default: %(default)s)",
                                      default="file-BXJvFq00QyBKgFj9PZBqgbXg")
argparser.add_argument("--gatk", help="GATK tarball (default: %(default)s)",
                                 default="file-BXK8p100QyB0JVff3j9Y1Bf5")
argparser.add_argument("--run-tests", help="run small test assemblies", action="store_true")
argparser.add_argument("--run-large-tests", help="run test assemblies of varying sizes", action="store_true")
# group = argparser.add_argument_group("filter")
# group.add_argument("--filter-targets", help="panel of target sequences (default: %(default)s)",
#                                 default="file-BXF0vf80QyBF509G9J12g9F2")
# group = argparser.add_argument_group("scaffold")
# group.add_argument("--scaffold-reference", help="Reference genome FASTA (default: %(default)s)",
#                                             default="file-BXF0vZ00QyBF509G9J12g944")
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
    applets = ["viral-ngs-human-depletion", "viral-ngs-filter", "viral-ngs-trinity", "viral-ngs-assembly-scaffolding",
               "viral-ngs-assembly-refinement", "viral-ngs-assembly-analysis"]

    # Build applets for assembly workflow in [args.folder]/applets/ folder
    project.new_folder(applets_folder, parents=True)
    for applet in applets:
        # TODO: reuse an existing applet with matching git_revision
        print "building {}...".format(applet),
        sys.stdout.flush()
        applet_dxid = json.loads(subprocess.check_output(["dx","build","--destination",args.project+":"+applets_folder+"/",os.path.join(here,applet)]))["id"]
        print applet_dxid
        applet = dxpy.DXApplet(applet_dxid, project=project.get_id())
        applet.set_properties({"git_revision": git_revision})

    # Build applets that user interact with directly in [args.folder]/ main folder
    exposed_applets = ["viral-ngs-fasta-fetcher"]
    for applet in exposed_applets:
        print "building {}...".format(applet),
        sys.stdout.flush()
        applet_dxid = json.loads(subprocess.check_output(["dx","build","--destination",args.project+":"+args.folder+"/",os.path.join(here,applet)]))["id"]
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

def build_workflows(speciesList):
    workflows = {}
    for species in speciesList:
        workflow = build_workflow(species, species_resource[species])
        workflows[species] = workflow
    return workflows

def build_workflow(species, resources):
    wf = dxpy.new_dxworkflow(title='viral-ngs-assembly_{0}'.format(species),
                              name='viral-ngs-assembly_{0}'.format(species),
                              description='viral-ngs-assembly, with resources populated for {0}'.format(species),
                              project=args.project,
                              folder=args.folder,
                              properties={"git_revision": git_revision})

    depletion_applet = find_applet("viral-ngs-human-depletion")
    depletion_applet_inputSpec = depletion_applet.describe()["inputSpec"]
    depletion_input = {
        "bmtagger_dbs": [x for x in depletion_applet_inputSpec if x["name"] == "bmtagger_dbs"][0]["default"],
        "blast_dbs": [x for x in depletion_applet_inputSpec if x["name"] == "blast_dbs"][0]["default"],
        "resources": [x for x in depletion_applet_inputSpec if x["name"] == "resources"][0]["default"]
    }
    depletion_stage_id = wf.add_stage(depletion_applet, stage_input=depletion_input, name="deplete", folder="intermediates")

    filter_input = {
        "reads": dxpy.dxlink({"stage": depletion_stage_id, "outputField": "cleaned_reads"}),
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    if "filter-targets" in resources:
        filter_input["targets"] = dxpy.dxlink(resources["filter-targets"])

    filter_stage_id = wf.add_stage(find_applet("viral-ngs-filter"), stage_input=filter_input, name="filter", folder="intermediates")

    trinity_input = {
        "reads": dxpy.dxlink({"stage": filter_stage_id, "outputField": "filtered_reads"}),
        "subsample": 100000,
        "min_base_count": 5000,
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    if "contaminants" in resources:
        trinity_input["contaminants"] = dxpy.dxlink(resources["contaminants"])

    trinity_stage_id = wf.add_stage(find_applet("viral-ngs-trinity"), stage_input=trinity_input, name="trinity", folder="intermediates")

    scaffold_input = {
        "trinity_contigs": dxpy.dxlink({"stage": trinity_stage_id, "outputField": "contigs"}),
        "trinity_reads": dxpy.dxlink({"stage": trinity_stage_id, "outputField": "subsampled_reads"}),
        "resources": dxpy.dxlink({"stage": depletion_stage_id, "inputField": "resources"})
    }
    if "scaffold-reference" in resources:
        scaffold_input["reference_genome"] = dxpy.dxlink(resources["scaffold-reference"])

    scaffold_stage_id = wf.add_stage(find_applet("viral-ngs-assembly-scaffolding"), stage_input=scaffold_input, name="scaffold", folder="intermediates")

    refine1_input = {
        "assembly": dxpy.dxlink({"stage": scaffold_stage_id, "outputField": "modified_scaffold"}),
        "reads": dxpy.dxlink({"stage": depletion_stage_id, "outputField": "cleaned_reads"}),
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

# Dict of species-name: workflow_id
workflows = build_workflows(args.species)

if args.run_tests is True or args.run_large_tests is True:
    muscle_applet = dxpy.DXApplet("applet-BXQxjv00QyB9QF3vP4BpXg95")

    # test data found in "bi-viral-ngs CI:/test_data"
    test_samples = {
        "SRR1553416": {
            "species": "Ebola",
            "reads": "file-BXBP0VQ011y0B0g5bbJFzx51",
            "reads2": "file-BXBP0Xj011yFYvPjgJJ0GzZB",
            "broad_assembly": "file-BXFqQvQ0QyB5859Vpx1j7bqq",
            "expected_assembly_sha256sum": "0aee68fa7a120e6a319dea3f3fb6f74243d928e7c54023799ea16de6322c67da",
            # contig is named >SRR1553416-0
            "expected_subsampled_base_count": 459632,
            "expected_alignment_base_count": 485406
        },
        "SRR1553554": {
            "species": "Ebola",
            "reads": "file-BXPPQ2Q0YzB28x9Q9911Ykz5",
            "reads2": "file-BXPPQ380YzB6xGxJ45K9Yv6Q",
            "broad_assembly": "file-BXQx6G00QyB6PQVYKQBgzxv4",
            "expected_assembly_sha256sum": "cdfeb7773bba47f72316dbd197b91130380ed9e165d5a1dde142257266092b54",
            # contig is named >SRR1553554-0
            "expected_subsampled_base_count":  467842,
            "expected_alignment_base_count": 590547
        }
    }

    if args.run_large_tests is True:
        # nb these samples takes too long for Travis
        test_samples["SRR1553468"] = {
            "species": "Ebola",
            "reads": "file-BXYqZj80Fv4YqP151Zy9291y",
            "reads2": "file-BXYqZkQ0Fv4YZYKx14yJg0b4",
            "broad_assembly": "file-BXYqYKQ0QyB84xYJP9Kz7zzK",
            "expected_assembly_sha256sum": "4460fbf7cc24e921e0eb3925713cc34fe58f6dfe9594954ff65da7cbcd71b093",
            # contig is named >SRR1553468-0
            "expected_subsampled_base_count": 18787806,
            "expected_alignment_base_count": 247110236
        }
        test_samples["G1190"] = {
            "species": "Lassa",
            "reads": "file-Bg97bJQ0x0z12q4XyZf5p0Kk",
            "broad_assembly": 'file-Bg533J00x0zBkYkFGb23k58B',
            "expected_assembly_sha256sum": "e7aa592e5ab9d3d1d3ac7fa1cc53eeff37e3ea30afad72a3cf9549172767c95c",
            # contig is named >G1190-0 and so on
            "expected_subsampled_base_count":  1841634,
            "expected_alignment_base_count": 111944259
        }

    test_analyses = []
    for test_sample in test_samples.keys():
        # create a subfolder for this sample
        test_folder = args.folder + "/" + test_sample
        project.new_folder(test_folder)
        # run the workflow on the test sample
        try:
            workflow = workflows[test_samples[test_sample]["species"]]
        except KeyError:
            # Skip running test if workflow for req species was not built
            continue

        test_input = {
            "deplete.file": dxpy.dxlink(test_samples[test_sample]["reads"]),
            "deplete.skip_depletion": True,
            "scaffold.novocraft_tarball": dxpy.dxlink(args.novocraft),
            "scaffold.gatk_tarball": dxpy.dxlink(args.gatk),
        }
        if "reads2" in test_samples[test_sample]:
            test_input["deplete.paired_fastq"] = dxpy.dxlink(test_samples[test_sample]["reads2"])

        test_analysis = workflow.run(test_input, project=project.get_id(), folder=test_folder, name=(git_revision+" "+test_sample))
        print "Launched {} for {}".format(test_analysis.get_id(), test_sample)
        test_analyses.append((test_sample,test_analysis))

    # wait for jobs to finish while working around Travis 10m console inactivity timeout
    print "Waiting for analyses to finish..."
    noise = subprocess.Popen(["/bin/bash", "-c", "while true; do date; sleep 60; done"])
    try:
        for (test_sample,test_analysis) in test_analyses:
            test_analysis.wait_on_done()
            workflow = workflows[test_samples[test_sample]["species"]]

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
        workflow = workflows[test_samples[test_sample]["species"]]
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
