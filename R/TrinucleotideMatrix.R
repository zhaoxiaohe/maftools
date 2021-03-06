#' Extract single 5' and 3' bases flanking the mutated site and estimate APOBAC enrichment score.
#' @details Extracts immediate 5' and 3' bases flanking the mutated site and classifies them into 96 substitution classes.
#' This function loads reference genome into memeory. Typical human geneome occupies a peak memory of ~3 gb while extracting bases.
#' 
#' APOBAC Enrichment: Enrichment score is calculated using the same method described by Roberts et al to estimate APOBAC enrichment.
#' 
#'                 E = (n_tcw * background_c) / (n_C * background_tcw)
#'        
#'  where, n_tcw = number of mutations within T[C>T]W and T[C>G]W context. W -> A or T
#'         n_C   = number of mutated C and G 
#'         background_C and background_tcw motifs are number of C and TCW motifs occuring around +/- 20bp of each mutation.
#'                 
#' One-sided Fisher's Exact test is performed to determine the enrichment of APOBAC tcw mutations over background.
#' 
#' @references Roberts SA, Lawrence MS, Klimczak LJ, et al. An APOBEC Cytidine Deaminase Mutagenesis Pattern is Widespread in Human Cancers. Nature genetics. 2013;45(9):970-976. doi:10.1038/ng.2702.
#' 
#'
#' @param maf an \code{\link{MAF}} object generated by \code{\link{read.maf}}
#' @param ref_genome faidx indexed refrence fasta file.
#' @param prefix Prefix to add or remove from contig names in MAF file.
#' @param add If prefix is used, default is to add prefix to contig names in MAF file. If false prefix will be removed from contig names.
#' @param ignoreChr Chromsomes to remove from analysis. e.g. chrM
#' @param useSyn Logical. Whether to include synonymous variants in analysis. Defaults to TRUE
#' @return A matrix of dimension nx96, where n is the number of samples in the MAF.
#' @examples
#' \dontrun{
#' laml.tnm <- trinucleotideMatrix(maf = laml, ref_genome = 'hg19.fa',
#' prefix = 'chr', add = TRUE, useSyn = TRUE)
#' }
#'
#' @importFrom VariantAnnotation getSeq seqlevels
#' @importFrom Biostrings subseq
#' @importFrom Rsamtools FaFile
#' @seealso \code{\link{extractSignatures}}
#' @export

trinucleotideMatrix = function(maf, ref_genome, prefix = NULL, add = TRUE, ignoreChr = NULL, useSyn = TRUE){

  #suppressPackageStartupMessages(require('VariantAnnotation', quietly = TRUE))
  #suppressPackageStartupMessages(require('Biostrings', quietly = TRUE))

  #Synonymous variants
  maf.silent = maf@maf.silent
  #Main data
  maf = maf@data

  #in case user read maf without removing silent variants, remove theme here.
  silent = c("3'UTR", "5'UTR", "3'Flank", "Targeted_Region", "Silent", "Intron",
             "RNA", "IGR", "Splice_Region", "5'Flank", "lincRNA")
  maf = maf[!Variant_Classification %in% silent] #Remove silent variants from main table

  if(useSyn){
    maf = rbind(maf, maf.silent, fill = TRUE)
  }

  #one bp up and down.
  up = down = 1

  #reate a reference to an indexed fasta file.
  ref = Rsamtools::FaFile(file = ref_genome)

  #Remove unwanted contigs
  if(!is.null(ignoreChr)){
    maf = maf[!maf$Chromosome %in% ignoreChr]
  }

  if(!is.null(prefix)){
    if(add){
      maf$Chromosome = paste(prefix,maf$Chromosome, sep = '')
    }else{
      maf$Chromosome = gsub(pattern = prefix, replacement = '', x = maf$Chromosome, fixed = TRUE)
    }
  }

  #seperate snps and indels
  maf.snp = maf[Variant_Type == 'SNP']
  if(nrow(maf) == 0){
    stop('No more single nucleotide variants left after filtering for SNP in Variant_Type field.')
  }
  #maf.rest = maf[!maf$Variant_Type %in% 'SNP']

  #get unique Chromosome names from maf
  chrs = unique(maf.snp$Chromosome)

  #read fasta
  message('reading fasta (this might take few minutes)..')
  ref = VariantAnnotation::getSeq(x = ref)

  #extract contigs from reference fasta
  seq.lvl = VariantAnnotation::seqlevels(ref)

  chrs.missing = chrs[!chrs %in% seq.lvl]

  #validation
  if(length(chrs.missing) > 0){
    message("contigs in fasta file:")
    print(seq.lvl)
    message("contigs in maf:")
    print(chrs)
    message('missing reference contigs from fasta file.')
    print(chrs.missing)
    message(paste0("Contig names in MAF must match to contig names in reference fasta. Ignorinig ", nrow(maf.snp[Chromosome %in% chrs.missing]) ," single nucleotide variants from ", paste(chrs.missing, collapse = ', ')))
    maf.snp = maf.snp[!Chromosome %in% chrs.missing]
  }

  #Meaure nucleotide frequency and tcw motifs within 20bp up and down of mutated base; 
  extract.tbl = data.table::data.table(Chromosome = maf.snp$Chromosome, Start = maf.snp$Start_Position-1, End = maf.snp$Start_Position+1,
                           Reference_Allele = maf.snp$Reference_Allele, Tumor_Seq_Allele2 = maf.snp$Tumor_Seq_Allele2,
                           Tumor_Sample_Barcode = maf.snp$Tumor_Sample_Barcode, upstream = maf.snp$Start_Position-20,
                           downstream = maf.snp$End_Position+20)

  message("Extracting 5' and 3' adjacent bases..")
  ss = Biostrings::subseq(x = ref[extract.tbl[,Chromosome]], start = extract.tbl[,Start] , end = extract.tbl[,End])
  
  message('Extracting +/- 20bp around mutated bases for background estimation..')
  updwn = Biostrings::subseq(x = ref[extract.tbl[,Chromosome]], start = extract.tbl[,upstream] , end = extract.tbl[,downstream])
  updwn.alphFreq = data.table::as.data.table( Biostrings::alphabetFrequency(x = updwn))[,.(A, C, G, T)] #Nucleotide frequency
  updwn.tnmFreq = data.table::as.data.table(Biostrings::trinucleotideFrequency(x = updwn, step = 1))
  
  extract.tbl[,trinucleotide:= as.character(ss)][,updown := as.character(updwn)]
  extract.tbl = cbind(extract.tbl, updwn.alphFreq[,.(A, T, G, C)])
  extract.tbl = cbind(extract.tbl, updwn.tnmFreq[,.(TCA, TCT, AGA, TGA)])
  extract.tbl[, tcw := rowSums(extract.tbl[,.(TCA, TCT)])]
  extract.tbl[, wga := rowSums(extract.tbl[,.(TGA, AGA)])]
  
  extract.tbl[,Substitution:=paste(extract.tbl$Reference_Allele, extract.tbl$Tumor_Seq_Allele2, sep='>')]
  extract.tbl$SubstitutionMotif = paste(substr(x = as.character(extract.tbl$trinucleotide), 1, 1),'[',extract.tbl$Substitution, ']', substr(as.character(extract.tbl$trinucleotide), 3, 3), sep='')

  #substitutions are referred to by the pyrimidine of the mutated Watson–Crick base pair
  conv = c("T>C", "T>C", "C>T", "C>T", "T>A", "T>A", "T>G", "T>G", "C>A", "C>A", "C>G", "C>G")
  names(conv) = c('A>G', 'T>C', 'C>T', 'G>A', 'A>T', 'T>A', 'A>C', 'T>G', 'C>A', 'G>T', 'C>G', 'G>C')
  
  extract.tbl$SubstitutionType = conv[extract.tbl$Substitution]
  extract.tbl$SubstitutionTypeMotif = paste(substr(x = as.character(extract.tbl$trinucleotide), 1, 1),'[',extract.tbl$SubstitutionType, ']', substr(as.character(extract.tbl$trinucleotide), 3, 3), sep='')
  
  #Compile data
  ##This is nucleotide frequcny and motif frequency across 41 bp.
  apobecSummary = extract.tbl[,.(A = sum(A), T= sum(T), G = sum(G), C = sum(C), tcw = sum(tcw), wga = sum(wga), bases = sum(A,T,G,C)), Tumor_Sample_Barcode]
  
  ##This is per sample conversion events
  sub.tbl = extract.tbl[,.N,.(Tumor_Sample_Barcode, Substitution)]
  sub.tbl = data.table::dcast(data = sub.tbl, formula = Tumor_Sample_Barcode ~ Substitution, fill = 0, value.var = 'N')
  sub.tbl[,n_A := rowSums(sub.tbl[,.(`A>C`, `A>G`, `A>T`)], na.rm = TRUE)][,n_T := rowSums(sub.tbl[,.(`T>A`, `T>C`, `T>G`)], na.rm = TRUE)][,n_G := rowSums(sub.tbl[,.(`G>A`, `G>C`, `G>T`)], na.rm = TRUE)][,n_C := rowSums(sub.tbl[,.(`C>A`, `C>G`, `C>T`)], na.rm = TRUE)]
  sub.tbl[,n_mutations := rowSums(sub.tbl[,.(n_A, n_T, n_G, n_C)], na.rm = TRUE)]
  sub.tbl[,"n_C>G_and_C>T" := rowSums(sub.tbl[,.(`C>G` + `G>C`, `C>T`, `G>A`)], na.rm = TRUE)] #number of APOBAC type mutations (C>G and C>T type)
  
  
  ##This is per substitution type events
  subType.tbl = extract.tbl[, .N, .(Tumor_Sample_Barcode, SubstitutionMotif)]
  subType.tbl = data.table::dcast(data = subType.tbl, formula = Tumor_Sample_Barcode ~ SubstitutionMotif, fill = 0, value.var = 'N')
  
  ###tCw events
  subType.tbl[, tCw_to_A := rowSums(subType.tbl[,.(`T[C>A]A`, `T[C>A]T`)], na.rm = TRUE)]
  subType.tbl[, tCw_to_G := rowSums(subType.tbl[,.(`T[C>G]A`, `T[C>G]T`)], na.rm = TRUE)]
  subType.tbl[, tCw_to_T := rowSums(subType.tbl[,.(`T[C>T]A`, `T[C>T]T`)], na.rm = TRUE)]
  subType.tbl[, tCw := rowSums(subType.tbl[,.(tCw_to_A, tCw_to_G, tCw_to_T)], na.rm = TRUE)]
  
  ###wGa events
  subType.tbl[, wGa_to_C := rowSums(subType.tbl[,.(`A[G>C]A`, `T[G>C]A`)], na.rm = TRUE)]
  subType.tbl[, wGa_to_T := rowSums(subType.tbl[,.(`A[G>T]A`, `T[G>T]A`)], na.rm = TRUE)]
  subType.tbl[, wGa_to_A := rowSums(subType.tbl[,.(`A[G>A]A`, `T[G>A]A`)], na.rm = TRUE)]
  subType.tbl[, wGa := rowSums(subType.tbl[,.(wGa_to_C, wGa_to_T, wGa_to_A)], na.rm = TRUE)]
  
  ##tCw_to_G+tCw_to_T
  subType.tbl[, "tCw_to_G+tCw_to_T" := rowSums(subType.tbl[,.(`T[C>G]T`, `T[C>G]A`, `T[C>T]T`, `T[C>T]A`, `T[G>C]A`, `A[G>C]A`, `T[G>A]A`, `A[G>A]A`)], na.rm = TRUE)]

  ###Merge data
  sub.tbl = merge(sub.tbl, subType.tbl[,.(tCw_to_A, tCw_to_T, tCw_to_G, tCw, wGa_to_C, wGa_to_T, wGa_to_A, wGa, `tCw_to_G+tCw_to_T`, Tumor_Sample_Barcode)], by = 'Tumor_Sample_Barcode')
  sub.tbl = merge(sub.tbl, apobecSummary, by = 'Tumor_Sample_Barcode')
  
  ###Estimate APOBAC enrichment
  sub.tbl[,APOBAC_Enrichment := (`tCw_to_G+tCw_to_T`/`n_C>G_and_C>T`)/(tcw/C)]
  sub.tbl[,non_APOBEC_mutations := n_mutations - `tCw_to_G+tCw_to_T`]
  data.table::setDF(sub.tbl)
  
  message("Estimating APOBAC enrichment scores.. ")
  apobac.fisher.dat = sub.tbl[,c(19, 28, 32, 33, 34)]
  apobac.fisher.dat = apply(X = apobac.fisher.dat, 2, as.numeric)

  ###One way Fisher test to estimate over representation og APOBAC associated tcw mutations
  message("Performing one-way Fisher's test for APOBAC enrichment..")
  sub.tbl = cbind(sub.tbl, data.table::rbindlist(apply(X = apobac.fisher.dat, 1, function(x){
    xf = fisher.test(matrix(c(x[2], sum(x[3], x[4]), x[1] - x[2], x[3]-x[4]), nrow = 2), alternative = 'g')
    data.table::data.table(fisher_pvalue = xf$p.value, or = xf$estimate, ci.up = xf$conf.int[1], ci.low = xf$conf.int[2])
  })))
  
  data.table::setDT(sub.tbl)
  colnames(sub.tbl)[29:35] = paste0("n_bg_", colnames(sub.tbl)[29:35])
  sub.tbl = sub.tbl[order(fisher_pvalue)]
  
  ##Choosing APOBAC Enrichment scores > 2 as cutoff
  sub.tbl$APOBAC_Enriched = ifelse(test = sub.tbl$APOBAC_Enrichment >2, yes = 'yes', no = 'no')
  
  message(paste0("APOBAC related mutations are enriched in "), round(nrow(sub.tbl[APOBAC_Enriched %in% 'yes']) / nrow(sub.tbl) * 100, digits = 3), "% of samples (APOBAC enrichment score >2 ; ", 
          nrow(sub.tbl[APOBAC_Enriched %in% 'yes']), " of " , nrow(sub.tbl), " samples)")
  
  message("Creating mutation matrix..")
  extract.tbl.summary = extract.tbl[,.N , by = list(Tumor_Sample_Barcode, SubstitutionTypeMotif)]

  colOrder = c("A[C>A]A", "A[C>A]C", "A[C>A]G", "A[C>A]T", "C[C>A]A", "C[C>A]C",
               "C[C>A]G", "C[C>A]T", "G[C>A]A", "G[C>A]C", "G[C>A]G", "G[C>A]T",
               "T[C>A]A", "T[C>A]C", "T[C>A]G", "T[C>A]T", "A[C>G]A", "A[C>G]C",
               "A[C>G]G", "A[C>G]T", "C[C>G]A", "C[C>G]C", "C[C>G]G", "C[C>G]T",
               "G[C>G]A", "G[C>G]C", "G[C>G]G", "G[C>G]T", "T[C>G]A", "T[C>G]C",
               "T[C>G]G", "T[C>G]T", "A[C>T]A", "A[C>T]C", "A[C>T]G", "A[C>T]T",
               "C[C>T]A", "C[C>T]C", "C[C>T]G", "C[C>T]T", "G[C>T]A", "G[C>T]C",
               "G[C>T]G", "G[C>T]T", "T[C>T]A", "T[C>T]C", "T[C>T]G", "T[C>T]T",
               "A[T>A]A", "A[T>A]C", "A[T>A]G", "A[T>A]T", "C[T>A]A", "C[T>A]C",
               "C[T>A]G", "C[T>A]T", "G[T>A]A", "G[T>A]C", "G[T>A]G", "G[T>A]T",
               "T[T>A]A", "T[T>A]C", "T[T>A]G", "T[T>A]T", "A[T>C]A", "A[T>C]C",
               "A[T>C]G", "A[T>C]T", "C[T>C]A", "C[T>C]C", "C[T>C]G", "C[T>C]T",
               "G[T>C]A", "G[T>C]C", "G[T>C]G", "G[T>C]T", "T[T>C]A", "T[T>C]C",
               "T[T>C]G", "T[T>C]T", "A[T>G]A", "A[T>G]C", "A[T>G]G", "A[T>G]T",
               "C[T>G]A", "C[T>G]C", "C[T>G]G", "C[T>G]T", "G[T>G]A", "G[T>G]C",
               "G[T>G]G", "G[T>G]T", "T[T>G]A", "T[T>G]C", "T[T>G]G", "T[T>G]T"
  )

  #colOrderClasses = rep(c('C>A', 'C>G', 'C>T', 'T>A', 'T>C', 'T>G'), each = 16)

  conv.mat = as.data.frame(data.table::dcast(extract.tbl.summary, formula = Tumor_Sample_Barcode~SubstitutionTypeMotif, fill = 0, value.var = 'N'))
  #head(conv.mat)
  rownames(conv.mat) = conv.mat[,1]
  #head(conv.mat)
  conv.mat = conv.mat[,-1]

  #conv.mat = t(t(conv.mat)[colOrder,])
  #Check for missing somatic mutation types (this is possible for cancer types with low mutation rate or for a cohort with lesser samples)
  colOrder.missing = colOrder[!colOrder %in% colnames(conv.mat)]
  #If any missing add them with zero counts
  if(length(colOrder.missing) > 0){
    zeroMat = as.data.frame(matrix(data = 0, nrow = nrow(conv.mat), ncol = length(colOrder.missing)))
    colnames(zeroMat) = colOrder.missing
    conv.mat = cbind(conv.mat, zeroMat)
  }

  conv.mat = as.matrix(conv.mat[,match(colOrder, colnames(conv.mat))]) #organize columns according to colOrder

  #Set NAs to zeros if any
  conv.mat[is.na(conv.mat)] = 0
  message(paste('matrix of dimension ', nrow(conv.mat), 'x', ncol(conv.mat), sep=''))
  return(list(nmf_matrix = conv.mat, APOBAC_scores = sub.tbl))
}
