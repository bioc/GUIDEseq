#' @importFrom S4Vectors Rle runValue mcols
#' @importFrom methods as
#' @importFrom IRanges IRanges viewWhichMaxs runLength runsum
#' ranges Views coverage
#' @importFrom GenomicRanges GRanges start score
#' @importFrom GenomeInfoDb seqlevels seqinfo seqnames
#' @importFrom matrixStats rowMins rowMaxs

.annotate <-
    function(from.gr, to.gr, peak.height.mcol ="count",
    bg.height.mcol = "bg", distance.threshold = 40,
    max.overlap.plusSig.minusSig = 10L,
    plus.strand.start.gt.minus.strand.end = TRUE, to.strand = "-",
    PeakLocForDistance = "start", FeatureLocForDistance = "TSS")
{
    if (length(names(from.gr)) < length(from.gr))
       names(from.gr) <- paste(seqnames(from.gr), start(from.gr), sep=":")
    if (length(names(to.gr)) < length(to.gr))
       names(to.gr) <- paste(seqnames(to.gr), start(to.gr), sep=":")

    gr <- annotatePeakInBatch(from.gr, featureType = "TSS",
        AnnotationData = to.gr, output="both",
        PeakLocForDistance = PeakLocForDistance,
        FeatureLocForDistance = FeatureLocForDistance,
        maxgap = distance.threshold)
    gr <- subset(gr, gr$peak != gr$feature)
    if (plus.strand.start.gt.minus.strand.end)
    {
        ann.peaks <- as.data.frame(gr[!is.na(gr$distancetoFeature) &
            gr$shortestDistance  <=  distance.threshold &
            ((abs(gr$distancetoFeature) <= max.overlap.plusSig.minusSig &
             gr$insideFeature != "downstream") |
            gr$insideFeature == "upstream"), ])
    }
    else
    {
        ann.peaks <- as.data.frame(gr[!is.na(gr$distancetoFeature) &
            gr$shortestDistance <= distance.threshold, ])
    }
    if (dim(as.data.frame(ann.peaks))[1] > 0)
    {
        to.peaks <- as.data.frame(to.gr)
        to.peaks <- cbind(feature = names(to.gr), to.peaks)
        metadata.col <- which(colnames(to.peaks) %in% names(mcols(to.gr)))
        colnames(to.peaks)[metadata.col] <-
            paste(to.strand, colnames(to.peaks)[metadata.col], sep=":")
        to.peaks <- to.peaks[, c(1, metadata.col)]
        temp1 <- merge(to.peaks, ann.peaks)
        temp1 <- cbind(temp1,
            totalCount = rowSums(temp1[,grep(peak.height.mcol,
            colnames(temp1))]))
        temp1$names <- paste(temp1$peak, temp1$feature, sep=":")
        temp1$minStart <- rowMins(as.matrix(
            temp1[, c("start_position", "start")]))
        temp1$maxEnd <- rowMaxs(as.matrix(temp1[, c("end_position", "end")]))
        bed.temp <- temp1[, c("seqnames", "minStart",
            "maxEnd", "names", "totalCount")]
        bed.temp <- cbind(bed.temp, strand = "+")
        if (length(intersect(names(mcols(to.gr)), bg.height.mcol))  > 0)
        {
            if(is.null(dim(temp1)))
            {
                temp1 <- c(temp1, sum(temp1[,grep(bg.height.mcol,
                    colnames(temp1))]))
            }
            else
            {
                temp1 <- cbind(temp1,
                    totalBg = rowSums(
                    temp1[,grep(bg.height.mcol, colnames(temp1))]))
            }
            mergedPeaks.gr <- GRanges(IRanges(start =
                as.numeric(as.character(bed.temp[,2])),
                end = as.numeric(as.character(bed.temp[,3])),
                names = bed.temp[,4]),
                seqnames = bed.temp[,1], strand = Rle("+", dim(bed.temp)[1]),
                count = as.numeric(as.character(bed.temp[,5])),
                bg = as.numeric(as.character(temp1$totalBg)))
        }
        else
        {
            mergedPeaks.gr <- GRanges(IRanges(
                start = as.numeric(as.character(bed.temp[,2])),
                end = as.numeric(as.character(bed.temp[,3])),
                names = bed.temp[,4]),
                seqnames = bed.temp[,1], strand = Rle("+", dim(bed.temp)[1]),
                count = as.numeric(as.character(bed.temp[,5])))
        }
        return(list(mergedPeaks = mergedPeaks.gr, bed = bed.temp,
            detailed.mergedPeaks = temp1, all.mergedPeaks = gr))
    }
}
.getReadLengthFromCigar <-function(cigar)
{
    if (is.na(cigar))
    {
        0
    }
    else if (length(grep("D", cigar) >0))
    {
        i <- substr(cigar, 1, nchar(cigar) - 1)
        sum(as.numeric(unlist(strsplit(gsub("^M", "", gsub("M|I|D|S", "M", i)),
            "M"))), na.rm = TRUE) - 2 * sum(as.numeric(lapply(unlist(strsplit(
            gsub("M|I|S", "M", i ), "M")), function(thisStr)
           {if (length(grep("D",thisStr)) >0)
               as.numeric(strsplit(thisStr, "D")[[1]][1]) else 0})))
    }
    else
    {
        i <- substr(cigar, 1, nchar(cigar) - 1)
        sum(as.numeric(unlist(strsplit(gsub("^M", "",
            gsub("M|I|D|S", "M", i)), "M"))), na.rm = TRUE)
    }
}
.getStrandedCoverage <-
function(gr, window.size = 20L, step = 10L,
   bg.window.size = 5000L, strand, min.reads = 10L)
{
    cvg <- coverage(gr)
    cvg <- Filter(length, cvg)
    observed <- runsum(cvg, k = window.size + 1, endrule = "constant")
    bg <- runsum(cvg, k = bg.window.size + 1, endrule = "constant")
    pos.value <- do.call(rbind, lapply(1:length(observed), function(i) {
        end <- cumsum(runLength(observed[[i]]))
        start <- end - runLength(observed[[i]]) + 1
        value <- runValue(observed[[i]])
        temp <- cbind(names(observed)[i], start, end, value)
        temp <- subset(temp, as.numeric(temp[,4]) >= min.reads)
        pos.bg <- as.numeric(temp[,2]) - ceiling((bg.window.size - window.size)/2)
        pos.bg[pos.bg < 1] <- 1
        bg.value <- as.data.frame(bg[[i]][pos.bg ])
        temp <- cbind(temp, bg.value)
        temp
    }))
    window.gr <- GRanges(IRanges(
        start = as.numeric(as.character(pos.value[,2])),
        end = as.numeric(as.character(pos.value[,3]))),
        seqnames = pos.value[,1], strand = Rle(strand, dim(pos.value)[1]),
        count = as.numeric(as.character(pos.value[,4])),
        bg = as.numeric(as.character(
            pos.value[,5])) / bg.window.size * window.size)
    window.gr
}
.getStrandedCoverage2 <- ## Assumes data from single chromosome!!
    function(gr, window.size = 20L, bg.window.size = 5000L,
             strand, min.reads = 10L)
{
    cvg <- coverage(gr)
    cvg <- Filter(length, cvg)
    observed <- runsum(cvg, k = window.size + 1, endrule = "constant")
    bg <- runsum(cvg, k = bg.window.size + 1, endrule = "constant")
    observed.gr <- as(observed, "GRanges")
    strand(observed.gr) <- strand
    observed.gr <- observed.gr[score(observed.gr) >= min.reads]
    bg.pos <- start(observed.gr) -
        as.integer(ceiling((bg.window.size - window.size)/2))
    bg.pos <- pmax(1L, bg.pos)
    bg.value <- unlist(bg[split(bg.pos, seqnames(observed.gr))],
                       use.names=FALSE)
    mcols(observed.gr)$bg <- as.numeric(bg.value / bg.window.size * window.size)
    seqlevels(observed.gr) <- seqlevels(gr)
    seqinfo(observed.gr) <- seqinfo(gr)
    observed.gr
}

.locMaxPos <- function(data.ranges, window.size, step, min.reads)
{
    if (length(data.ranges) > 1)
    {
        total <- max(start(data.ranges))
        max.count <- numeric()
        i <- min(start(data.ranges))
        max.pos <- max.count
        j <- 0
        while (i <= total){
            this.range <- data.ranges[start(data.ranges) >= i &
                start(data.ranges) < (i + window.size)]
            i <- i + step
            if (length(this.range) > 1)
            {
                max.ind <- this.range[which.max(as.numeric(
                    as.character(this.range$count)))]
                max.pos <- c(start(max.ind), max.pos)
                max.count <- c(max.ind$count, max.count)
            }
            else if (length(this.range) == 1)
            {
                max.pos <- c(start(this.range), max.pos)
                max.count <- c(as.numeric(as.character(this.range$count)),
                    max.count)
            }

            nextI <- which(start(data.ranges) > i)
            if (length(nextI) > 0L) {
                j <- min(nextI)
                ##print(paste("j = ", j))
                if (start(data.ranges)[j] >= (i + window.size))
                {
                    i <- start(data.ranges)[j]
                }
            }
            local.max.start <- unique(max.pos[max.count >= min.reads])
        }
    }
    else
    {
        local.max.start <- start(data.ranges[data.ranges$count >= min.reads])
    }
    #list(max.pos,  max.count)
    local.max.start
}

### While these functions take GRanges, they assume ranges on one sequence

.locMaxPos2 <- function(gr, window.size, step) {
    cov <- coverage(ranges(gr), weight=score(gr))
    starts <- seq((min(start(gr)) %/% step) * step, max(start(gr)), step)
    windows <- IRanges(starts, width=window.size)
    viewWhichMaxs(Views(cov, windows))
}

.findProminentPeaks <- function(gr, maxgap) {
    cov <- coverage(ranges(gr), weight=score(gr))
    windows <- ranges(gr) + maxgap
    maxs <- viewWhichMaxs(Views(cov, windows))
    self.max <- ranges(gr) %pover% maxs
    gr[self.max]
}
