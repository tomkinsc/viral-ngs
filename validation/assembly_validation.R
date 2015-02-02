require(ggplot2)

d <- read.delim("/tmp/postmortem.txt",header=FALSE)
colnames(d) <- c("validation_result","sample","filtered_base_count",
                "subsampled_base_count","mean_coverage_depth",
                "consensus_length","identical","pct_identical",
                "N","gap","other","price")
d <- data.frame(d)

qplot(log(d[,"filtered_base_count"],10), log(d[,"subsampled_base_count"],10),
      xlab="filtered base count (log10)", ylab="subsampled base count (log10)")

qplot(log(d[,"filtered_base_count"],10), log(d[,"mean_coverage_depth"],10),
      xlab="filtered base count (log10)", ylab="mean coverage depth (log10)")

qplot(log(d[,"subsampled_base_count"],10), d[,"pct_identical"],
      xlab="subsampled base count (log10)", ylab="assembly consensus identity")

qplot(log(d[,"mean_coverage_depth"],10), d[,"pct_identical"],
      xlab="mean coverage depth (log10)", ylab="assembly consensus identity")

sum(d[,"price"])
