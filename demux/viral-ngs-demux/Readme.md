# Viral NGS Illumina Demux

Perform BCL conversion and de-multiplexing from Illumina RUN directory using viral-ngs' custom demux script.

This app is set up to complement DNAnexus incremental upload tool, and anticipates a record object (typically produced by incremental upload) as an input. The sentinel record must have, minimally, a `details` field named `tar_file_ids` which gives a list of tar file-ids (on the DNAnexus platform) that can be unpacked to constitute the RUN directory.

Alternatively, the user can specify an array of `Run Tarballs` which reconstitute the run directory when decompressed in sequence. The onus is on the user to ascertain completeness of run directory. Only minimal integrity checks will be imposed on by the program.

This applet outputs a series of demultiplexed unmapped bam files, as well as a metric file for QC purposes.

## Parameters
- Resources: The tarball containing resources from the [viral-ngs project](https://github.com/broadinstitute/viral-ngs). This is typically pre-filled for your convenience.
- Incremental upload sentinel record: The sentinel record produced by the the incremental_upload.sh script. When this record is closed it indicates that the upload is complete and demux can begin.
- Run Tarballs: Tarball(s), supplied in the order that they should be untarred in, which reconstitute the RUN folder of a single sequencing run.
- Lanes: An array of lanes to perform demux on. If not specified, demux will be performed on all lanes, as inferred from RunInfo.xml.
- Metric filename: Filename for the metric file that the demultiplexing tool generates.
- Barcode filename: Filename for output CommonBarcodes report.
- Per Sample Output: When set to true, create a subfolder for each sample, where all output files for each sample (unmapped bam, barcode report) will be stored.
- Sample Sheet: Override SampleSheet: Input tab or CSV file w/header and four named columns:barcode_name, library_name, barcode_sequence_1, barcode_sequence_2. Default is to look for a SampleSheet.csv in the inDir.
- Flowcell ID (Optional): ID of the flowcell. If specified, overrides flowcell ID found in the <flowcell> element of RunInfo.xml)
- Read Structure (Optional): Structure of reads. If specified, overrides the structure parsed from RunInfo.xml. A sample read structure is of the form "28T8M8B8S28T" which splits the read into 4 reads (28 cycles of template | 8 cycles of barcode | 8 cycles skipped | 28 bases of template). For more information, refer to the ExtractIlluminaBarcode function in the [picard toolsuite](https://broadinstitute.github.io/picard/command-line-overview.html)
- Sequencing Center: Name of the sequencing center
- Advanced options (Optional): Additional command line options that can be passed into the demux applet. Please refer to the [upstream documentation](http://viral-ngs.readthedocs.org/en/latest/illumina.html?highlight=demultiplex) for the full list of available options.


