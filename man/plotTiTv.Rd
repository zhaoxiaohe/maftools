% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plotTiTv.R
\name{plotTiTv}
\alias{plotTiTv}
\title{Plot Transition and Trasnversion ratios.}
\usage{
plotTiTv(res = NULL, plotType = "both", file = NULL, width = 6,
  height = 5, color = NULL, showBarcodes = FALSE, textSize = 2)
}
\arguments{
\item{res}{results generated by \code{\link{titv}}}

\item{plotType}{Can be 'bar', 'box' or 'both'. Defaults to 'both'}

\item{file}{basename for output file name. If given pdf will be generated.}

\item{width}{width of the plot, in inches.}

\item{height}{height of the plot, in inches.}

\item{color}{named vector of colors for each coversion class.}

\item{showBarcodes}{Whether to include sample names for barplot}

\item{textSize}{fontsize if showBarcodes is TRUE. Deafult 2.}
}
\value{
None.
}
\description{
Takes results generated from \code{titv} and plots the Ti/Tv ratios and contributions of 6 mutational conversion classes in each sample.
}
\examples{
laml.maf <- system.file("extdata", "tcga_laml.maf.gz", package = "maftools")
laml <- read.maf(maf = laml.maf, removeSilent = TRUE, useAll = FALSE)
laml.titv = titv(maf = laml, useSyn = TRUE)
plotTiTv(laml.titv)

}
\seealso{
\code{\link{titv}}
}
