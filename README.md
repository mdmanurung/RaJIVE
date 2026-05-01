
<!-- README.md is generated from README.Rmd. Please edit that file -->

# RaJIVE

<!-- badges: start -->

<!-- badges: end -->

RaJIVE (Robust Angle based Joint and Individual Variation Explained) is
a robust alternative to the aJIVE method for the estimation of joint and
individual components in the presence of outliers in multi-source data.
It decomposes the multi-source data into joint, individual and residual
(noise) contributions. The decomposition is robust with respect to
outliers and other types of noises present in the data.

## Installation

You can install the released version of RaJIVE from
[CRAN](https://CRAN.R-project.org) with:

``` r
install.packages("RaJIVE")
```

And the development version from [GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("mdmanurung/RaJIVE")
```

## Example

This is a basic example which shows how to use RaJIVE on simple
simulated data:

### Running robust aJIVE

``` r
library(RaJIVE)
## basic example code
n <- 50
pks <- c(100, 80, 50)
Y <- ajive.data.sim(K =3, rankJ = 3, rankA = c(7, 6, 4), n = n,
                   pks = pks, dist.type = 1)

initial_signal_ranks <-  c(7, 6, 4)
data.ajive <- list((Y$sim_data[[1]]), (Y$sim_data[[2]]), (Y$sim_data[[3]]))
ajive.results.robust <- Rajive(data.ajive, initial_signal_ranks)
```

The function returns a list containing the aJIVE decomposition, with the
joint component (shared across data sources), individual component (data
source specific) and residual component for each data source.

### Visualizing results:

  - Joint rank:

<!-- end list -->

``` r

get_joint_rank(ajive.results.robust)
#> [1] 3
```

  - Individual ranks:

<!-- end list -->

``` r
get_individual_rank(ajive.results.robust, 1)
#> [1] 5
get_individual_rank(ajive.results.robust, 2)
#> [1] 3
get_individual_rank(ajive.results.robust, 3)
#> [1] 1
```

  - Heatmap decomposition:

<!-- end list -->

``` r
decomposition_heatmaps_robustH(data.ajive, ajive.results.robust)
```

<img src="man/figures/README-unnamed-chunk-3-1.png" width="100%" />

  - Proportion of variance explained:

<!-- end list -->

``` r
showVarExplained_robust(ajive.results.robust, data.ajive)
#> $Joint
#> [1] 0.3148569 0.3349692 0.4197429
#> 
#> $Indiv
#> [1] 0.5499653 0.4156423 0.1522468
#> 
#> $Resid
#> [1] 0.1351778 0.2493886 0.4280103
```

  - Block scores and loadings:

<!-- end list -->

``` r
# Joint scores for block 1
get_block_scores(ajive.results.robust, k = 1, type = "joint")

# Individual loadings for block 2
get_block_loadings(ajive.results.robust, k = 2, type = "individual")
```

### Jackstraw significance testing

After running the RaJIVE decomposition, you can test which variables in
each data block have statistically significantly non-zero joint loadings
using the jackstraw permutation test:

``` r
# Run jackstraw test (increase n_null to 50-100 for publication-quality results)
js <- jackstraw_rajive(ajive.results.robust, data.ajive,
                       alpha = 0.05, n_null = 10,
                       correction = "bonferroni")

# Print a concise summary table
print(js)

# Get a data frame summary
summary(js)
```

  - Retrieve significant variables for a given block and component:

<!-- end list -->

``` r
get_significant_vars(js, block = 1, component = 1)
```

  - Visualize jackstraw results (three plot types available):

<!-- end list -->

``` r
# P-value histogram
plot_jackstraw(js, type = "pvalue_hist", block = 1, component = 1)

# F-statistic vs -log10(p-value) scatter plot
plot_jackstraw(js, type = "scatter", block = 1, component = 1)

# Heatmap of -log10(p-value) across all joint components for one block
plot_jackstraw(js, type = "loadings_significance", block = 1)
```

