# Viral NGS Illumina Demux

Perform BCL conversion and de-multiplexing from Illumina RUN directory using viral-ngs' custom demux script.

This app is set up to complement DNAnexus incremental upload tool, and anticipates a record object (typically produced by incremental upload) as an input. The sentinel record must have, minimally, a `details` field named `tar_file_ids` which gives a list of tar file-ids (on the DNAnexus platform) that can be unpacked to constitute the RUN directory.

This applet outputs a series of demultiplexed unmapped bam files, as well as a metric file for QC purposes.

## Parameters
- resources: The tarball containing resources from the [viral-ngs project](https://github.com/broadinstitute/viral-ngs). This is typically pre-filled for your convenience.
- Lane Number: This applet performs demultiplexing by lane. For a single-lane instrument such as MiSeq, this parameter should be set to 1 (default to 1).
- Metric filename: Filename for the metric file that the demultiplexing tool generates.
- Flowcell ID (Optional): ID of the flowcell. If specified, overrides flowcell ID found in the <flowcell> element of RunInfo.xml)
- Read Structure (Optional): Structure of reads. If specified, overrides the structure parsed from RunInfo.xml. A sample read structure is of the form "28T8M8B8S28T" which splits the read into 4 reads (28 cycles of template | 8 cycles of barcode | 8 cycles skipped | 28 bases of template). For more information, refer to the ExtractIlluminaBarcode function in the [picard toolsuite](https://broadinstitute.github.io/picard/command-line-overview.html)
- Sequencing Center: Name of the sequencing center
- Advanced options (Optional): Additional command line options that can be passed into the demux applet. Please refer to the [upstream documentation](http://viral-ngs.readthedocs.org/en/latest/illumina.html?highlight=demultiplex) for the full list of available options.


