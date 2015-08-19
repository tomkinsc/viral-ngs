# Viral NGS Fasta Fetcher

## What does this applet do?

This applet fetches genomic fasta files for organisms of given accession numbers from Genbank.

## Parameters
- resources: The tarball containing resources from the [viral-ngs project](https://github.com/broadinstitute/viral-ngs). This is typically pre-filled for your convenience.
- accession_numbers: A list of NCBI accession numbers corresponding to the organisms/strains whose genomic fasta files are to be fetched. This can be provided as a space-delimited (NC_004296.1 NC_004297.1) or comma-delimited (NC_004296.1, NC_004297.1) string.
- user_email: A valid email address is requested by NCBI for load/abuse notifications.
- combined_genome_prefix: the output file will be named [combined_genome_prefix].fasta
