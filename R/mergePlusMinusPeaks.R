#' Merge peaks from plus strand and minus strand
#'
#' Merge peaks from plus strand and minus strand with required orientation and
#' within certain distance apart
#'
#'
#' @param peaks.gr Specify the peaks as GRanges object, which should contain
#' peaks from both plus and minus strand. In addition, it should contain peak
#' height metadata column to store peak height and optionally background
#' height.
#' @param peak.height.mcol Specify the metadata column containing the peak
#' height, default to count
#' @param bg.height.mcol Specify the metadata column containing the background
#' height, default to bg
#' @param distance.threshold Specify the maximum gap allowed between the plus
#' stranded and the negative stranded peak, default 40. Suggest set it to twice
#' of window.size used for peak calling.
#' @param max.overlap.plusSig.minusSig Specify the cushion distance to allow
#' sequence error and inprecise integration Default to 30 to allow at most 10
#' (30-window.size 20) bp (half window) of minus-strand peaks on the right side
#' of plus-strand peaks. Only applicable if
#' plus.strand.start.gt.minus.strand.end is set to TRUE.
#' @param plus.strand.start.gt.minus.strand.end Specify whether plus strand
#' peak start greater than the paired negative strand peak end. Default to TRUE
#' @param output.bedfile Specify the bed output file name, which is used for
#' off target analysis subsequently.
#' @return output a list and a bed file containing the merged peaks a data
#' frame of the bed format \item{mergedPeaks.gr}{merged peaks as GRanges}
#' \item{mergedPeaks.bed}{merged peaks in bed format}
#' @author Lihua Julie Zhu
#' @references Zhu L.J. et al. (2010) ChIPpeakAnno: a Bioconductor package to
#' annotate ChIP-seq and ChIP-chip data. BMC Bioinformatics 2010,
#' 11:237doi:10.1186/1471-2105-11-237. Zhu L.J. (2013) Integrative analysis of
#' ChIP-chip and ChIP-seq dataset.  Methods Mol Biol. 2013;1067:105-24. doi:
#' 10.1007/978-1-62703-607-8\_8.
#' @keywords misc
#' @importFrom utils write.table
#' @importFrom GenomicRanges mcols strand start end seqnames
#' @examples
#'
#'
#' if (interactive())
#' {
#'     data(peaks.gr)
#'     mergedPeaks <- mergePlusMinusPeaks(peaks.gr = peaks.gr,
#'         output.bedfile = "mergedPeaks.bed")
#'     mergedPeaks$mergedPeaks.gr
#'     head(mergedPeaks$mergedPeaks.bed)
#' }
#'
#' @export mergePlusMinusPeaks
mergePlusMinusPeaks <-
    function(peaks.gr, peak.height.mcol ="count",
    bg.height.mcol = "bg", distance.threshold = 40L,
    max.overlap.plusSig.minusSig = 30L,
    plus.strand.start.gt.minus.strand.end = TRUE, output.bedfile)
{
    if (missing(peaks.gr)) {
        stop("Missing required peak input peaks.gr! \n")
    }
    if (class(peaks.gr) != "GRanges" ) {
        stop("No valid peaks.gr passed in. It needs to be GRanges object \n")
    }
    if (missing(output.bedfile))
    {
        stop("Missing required bed output file \n")
    }
    if (length(intersect(names(mcols(peaks.gr)), peak.height.mcol))  == 0)
        stop(paste(peak.height.mcol, "is not a valid metadata column.\n Please",
            "specify a valid metadata column with peak height in peaks.gr \n"))
    names(peaks.gr) <- paste(paste(seqnames(peaks.gr), strand(peaks.gr), sep=""),
        start(peaks.gr),end(peaks.gr), sep=":")
    pos.gr <- subset(peaks.gr, strand(peaks.gr) %in% c( "+", "*"))
    neg.gr <- subset(peaks.gr, strand(peaks.gr) == "-")
    ### peaks from both strand or present in both library
    if (length(pos.gr) >0 && length(neg.gr) > 0)
    {
        mergedPeaks <- .annotate(from.gr = pos.gr, to.gr = neg.gr,
           peak.height.mcol = peak.height.mcol,
           bg.height.mcol = bg.height.mcol,
           distance.threshold = distance.threshold,
           max.overlap.plusSig.minusSig = max.overlap.plusSig.minusSig,
           plus.strand.start.gt.minus.strand.end =
           plus.strand.start.gt.minus.strand.end,
           to.strand = "-")
    }
    if (length(pos.gr) == 0 || length(neg.gr) == 0 || length(mergedPeaks) == 0)
    {
        #### fake merge to get the same formated output even there is only one strand
        mergedPeaks <- .annotate(from.gr = peaks.gr, to.gr = peaks.gr,
            peak.height.mcol = peak.height.mcol,
            bg.height.mcol = bg.height.mcol,
            distance.threshold = distance.threshold,
            max.overlap.plusSig.minusSig = max.overlap.plusSig.minusSig,
            plus.strand.start.gt.minus.strand.end = FALSE,
            to.strand = "-",
            PeakLocForDistance = "middle", FeatureLocForDistance = "middle")
    }
    if (length(mergedPeaks) == 0)
    {
        mergedPeaks.gr <- ""
        temp <- data.frame(peaks.gr)
        bed.s <-  ""
        ann.peaks <- ""
        peaks.1strandOnly <- peaks.gr
        bed.m1 <- ""
        bed.m2 <- ""
    }
    else {
        mergedPeaks.gr <- mergedPeaks$mergedPeaks
        bed <- mergedPeaks$bed
    #mergedPeaksFromPlus2Minus <- mergedPeaks$all.mergedPeaks
        ann.peaks <- mergedPeaks$detailed.mergedPeaks
        if (length(pos.gr) == 0 || length(neg.gr) == 0)
        {
    	     peaks.1strandOnly <- peaks.gr[!names(peaks.gr) %in%
                 as.character(ann.peaks$feature) &
                 ! names(peaks.gr) %in% ann.peaks$peak]
        }
        else
        {
            neg.gr2 <- neg.gr[!names(neg.gr) %in%
                as.character(ann.peaks$feature)]
            pos.gr2 <- pos.gr[!names(pos.gr) %in% ann.peaks$peak]
            peaks.1strandOnly <- c(pos.gr2, neg.gr2)
        }
######### plus strand peaks merged to multiple peaks in the other strand
        temp <- as.data.frame(table(ann.peaks$peak))
######### minus strand peaks merged to multiple peaks in the other strand
        temp1 <- as.data.frame(table(ann.peaks$feature))
#########  details for peaks merged to multiple peaks in the other strand
        bed.m1 <- do.call(rbind, lapply(temp[temp[,2] > 1,1], function(loc) {
            thisLoc <- ann.peaks[ann.peaks$peak == loc,]
            minStart <- min(thisLoc$minStart)
            maxEnd <- max(thisLoc$maxEnd)
            totalCount <- sum(thisLoc$totalCount) - sum(thisLoc$count) + thisLoc$count[1]
            names <- paste(thisLoc$names[1], paste(thisLoc$feature[-1], collapse = ":"), sep=":")
                c(as.character(thisLoc$seqnames[1]), minStart, maxEnd, names, totalCount, "+")
        }))

        bed.m2 <- do.call(rbind, lapply(temp1[temp1[,2] > 1,1], function(loc) {
            thisLoc <- ann.peaks[ann.peaks$feature == loc,]
            minStart <- min(thisLoc$minStart)
            maxEnd <- max(thisLoc$maxEnd)
            totalCount <- sum(thisLoc$totalCount) - sum(thisLoc$`-:count`) + thisLoc$`-:count`[1]
            names <- paste(paste(thisLoc$peak[-1], collapse = ":"), thisLoc$names[1], sep=":")
            c(as.character(thisLoc$seqnames[1]), minStart, maxEnd, names, totalCount, "+")
        }))

        names.m1 <- ann.peaks[ann.peaks$peak %in% temp[temp[,2] > 1,1],]$names
        names.m2 <- ann.peaks[ann.peaks$feature %in% temp1[temp1[,2] > 1,1],]$names
        bed.s <- bed[ !bed$names %in% c( names.m1, names.m2), ]

        if (length(bed.m1) >0)
        {
            colnames(bed.m1) <- colnames(bed.s)
            bed.s <- rbind(bed.s, bed.m1)
        }
        if (length(bed.m2) > 0)
        {
            colnames(bed.m2) <- colnames(bed.s)
            bed.s <- rbind(bed.s,  bed.m2)
        }
     } ### if mergedPeaks null or not
     write.table(bed.s, file = output.bedfile, sep = "\t",
         col.names = FALSE, row.names=FALSE, quote=FALSE)
     list(bed.m1 = bed.m1, bed.m2 = bed.m2, mergedPeaks.gr = mergedPeaks.gr,
            mergedPeaks.bed = bed.s,
            peaks.1strandOnly = peaks.1strandOnly, mergedPeaks.details = ann.peaks)
}
