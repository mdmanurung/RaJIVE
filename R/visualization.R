# visualization.R — Interpretation and diagnostic helpers for rajiveplus
#
# Public API:
#   extract_components()   — extract tidy data / diagnostic payload from Rajive output
#   rank_features()        — rank features by loading, contribution, overlap, or significance
#   plot_components()      — unified plotting entry point
#   associate_components() — association between component scores and metadata
#   assess_stability()     — bootstrap stability assessment (joint rank / loadings)
#
# Aliases (thin wrappers over rank_features):
#   get_top_loadings()
#   get_feature_contributions()
#   compare_feature_sets_across_blocks()
#   summarize_significant_vars()
#
# Internal helpers (not exported):
#   .extract_rank_diagnostics()
#   .plot_rank_threshold()
#   .plot_bound_distributions()
#   .plot_ajive_diagnostic()
#   .procrustes_align()       — orthogonal Procrustes alignment for loading stability
#   .rf_resolve_method()      — method validation for rank_features
#   .rf_get_loadings()        — loading matrix accessor for rank_features
#   .rf_loading_df()          — top_loadings / contribution worker
#   .rf_overlap()             — overlap worker
#   .rf_significant()         — significant worker


# ---------------------------------------------------------------------------
# extract_components
# ---------------------------------------------------------------------------

#' Extract components or diagnostics from a Rajive decomposition
#'
#' Retrieves structured information from the output of \code{\link{Rajive}}.
#' Currently supports \code{what = "rank_diagnostics"} which returns the joint
#' rank selection diagnostics (observed singular values, Wedin/random-direction
#' bound samples, cutoffs, and identifiability-dropped components).
#'
#' @param ajive_output An object of class \code{"rajive"} (output of
#'   \code{\link{Rajive}}).
#' @param what Character scalar. What to extract.  Only
#'   \code{"rank_diagnostics"} is currently implemented.
#' @param format Character. \code{"wide"} (default) returns a named list of
#'   class \code{c("rajive_diagnostics", "list")}; \code{"long"} returns a
#'   tidy \code{data.frame} with one row per observed singular value.
#' @param include_meta Logical. If \code{TRUE}, additional metadata fields
#'   useful for plot labels are included in the wide list.
#' @param ... Reserved for future arguments.
#'
#' @return For \code{what = "rank_diagnostics"} and \code{format = "wide"}: a
#'   named list of class \code{c("rajive_diagnostics", "list")} containing:
#'   \describe{
#'     \item{\code{obs_svals}}{Numeric vector of observed common singular values.}
#'     \item{\code{obs_svals_sq}}{Numeric vector of squared common singular values.}
#'     \item{\code{joint_rank_estimate}}{Integer joint rank.}
#'     \item{\code{overall_sv_sq_threshold}}{Numeric combined threshold or
#'       \code{NA_real_} when no bounds were computed.}
#'     \item{\code{wedin_samples}}{Numeric vector of Wedin bound samples, or
#'       \code{NULL}.}
#'     \item{\code{rand_dir_samples}}{Numeric vector of random-direction bound
#'       samples, or \code{NULL}.}
#'     \item{\code{wedin_cutoff}}{5th-percentile Wedin threshold or
#'       \code{NA_real_}.}
#'     \item{\code{rand_cutoff}}{95th-percentile random-direction threshold or
#'       \code{NA_real_}.}
#'     \item{\code{wedin_percentile}}{Percentile used for Wedin cutoff (5) or
#'       \code{NA_real_}.}
#'     \item{\code{rand_percentile}}{Percentile used for random cutoff (95) or
#'       \code{NA_real_}.}
#'     \item{\code{identif_dropped}}{Integer vector of component indices
#'       dropped by the identifiability check (length 0 when none dropped).}
#'     \item{\code{cutoff_rule}}{One of \code{"max(wedin, random)"},
#'       \code{"wedin_only"}, \code{"random_only"}, \code{"none_available"}.}
#'     \item{\code{has_wedin}}{Logical.}
#'     \item{\code{has_random}}{Logical.}
#'   }
#'   For \code{format = "long"}: a \code{data.frame} with columns
#'   \code{component_index}, \code{obs_sval}, \code{obs_sval_sq},
#'   \code{classification}, \code{joint_rank_estimate},
#'   \code{overall_sv_sq_threshold}, \code{wedin_cutoff}, \code{rand_cutoff}.
#'
#' @examples
#' \donttest{
#' n   <- 40; pks <- c(30, 20)
#' Y   <- ajive.data.sim(K = 2, rankJ = 2, rankA = c(4, 3),
#'                       n = n, pks = pks, dist.type = 1)
#' fit <- Rajive(Y$sim_data, c(4, 3))
#' diag_wide <- extract_components(fit, what = "rank_diagnostics")
#' diag_long <- extract_components(fit, what = "rank_diagnostics", format = "long")
#' }
#'
#' @export
extract_components <- function(ajive_output,
                               what   = "rank_diagnostics",
                               format = c("wide", "long"),
                               include_meta = FALSE,
                               ...) {
  format <- match.arg(format)

  if (!identical(what, "rank_diagnostics")) {
    stop(sprintf(
      "what = '%s' is not supported. Currently only 'rank_diagnostics' is implemented.",
      what), call. = FALSE)
  }

  if (!inherits(ajive_output, "rajive")) {
    stop("ajive_output must be of class 'rajive'.", call. = FALSE)
  }

  .extract_rank_diagnostics(ajive_output, format = format, include_meta = include_meta)
}


# ---------------------------------------------------------------------------
# plot_components
# ---------------------------------------------------------------------------

#' Plot AJIVE diagnostic visualizations
#'
#' Produces diagnostic plots from the output of \code{\link{Rajive}}.  Three
#' plot types are supported:
#' \describe{
#'   \item{\code{"rank_threshold"}}{Squared observed singular values with
#'     Wedin and/or random-direction cutoff lines, colored by joint/nonjoint
#'     classification.  The active threshold is the
#'     \code{max(wedin, random_direction)} rule — a practical heuristic that
#'     is conservative in practice but does not carry formal FWER or FDR
#'     control for rank selection (see \code{StatisticalAudits.md}, Finding 6).}
#'   \item{\code{"bound_distributions"}}{Histogram(s) of Wedin and/or
#'     random-direction bound samples with percentile cutoff lines.}
#'   \item{\code{"ajive_diagnostic"}}{Full composite panel combining the
#'     threshold plot (top) with bound-distribution histograms (bottom).
#'     Requires the \pkg{patchwork} package.}
#' }
#'
#' @param ajive_output An object of class \code{"rajive"} (output of
#'   \code{\link{Rajive}}), or \code{NULL} when a precomputed diagnostics
#'   payload is supplied via \code{diagnostics}.
#' @param plot_type Character.  One of \code{"ajive_diagnostic"},
#'   \code{"rank_threshold"}, or \code{"bound_distributions"}.
#' @param ... Additional arguments passed to the plot helpers:
#'   \describe{
#'     \item{\code{diagnostics}}{Precomputed diagnostics list from
#'       \code{extract_components(..., what = "rank_diagnostics")}.  When
#'       supplied, \code{ajive_output} is ignored.}
#'     \item{\code{theme_fn}}{A \code{ggplot2} theme function; defaults to
#'       \code{ggplot2::theme_bw}.}
#'     \item{\code{cutoff_quantile}}{Numeric in (0, 1). Override the
#'       percentile cutoff for bound-distribution plots (default: use the
#'       cutoffs stored in the diagnostics payload).}
#'   }
#'
#' @return A \code{ggplot} object (or a \pkg{patchwork} composite for
#'   \code{plot_type = "ajive_diagnostic"}).
#'
#' @section Variance explained language:
#'   When variance-explained plots are added in a future phase, outputs will
#'   distinguish \emph{joint} variance explained from
#'   \emph{block-specific individual} variance explained after joint signal
#'   removal.  The two quantities are not interchangeable and should not be
#'   described with generic PCA-style language (StatisticalAudits.md, Finding 7).
#'
#' @examples
#' \donttest{
#' n   <- 40; pks <- c(30, 20)
#' Y   <- ajive.data.sim(K = 2, rankJ = 2, rankA = c(4, 3),
#'                       n = n, pks = pks, dist.type = 1)
#' fit <- Rajive(Y$sim_data, c(4, 3))
#' plot_components(fit, plot_type = "rank_threshold")
#' plot_components(fit, plot_type = "bound_distributions")
#' plot_components(fit, plot_type = "ajive_diagnostic")
#' }
#'
#' @export
plot_components <- function(ajive_output = NULL,
                            plot_type = c("ajive_diagnostic",
                                          "rank_threshold",
                                          "bound_distributions"),
                            ...) {
  plot_type <- match.arg(plot_type)
  dots <- list(...)

  # Resolve diagnostics payload
  diag <- if (!is.null(dots$diagnostics)) {
    dots$diagnostics
  } else if (!is.null(ajive_output)) {
    if (!inherits(ajive_output, "rajive")) {
      stop("ajive_output must be of class 'rajive'.", call. = FALSE)
    }
    extract_components(ajive_output, what = "rank_diagnostics", format = "wide")
  } else {
    stop("ajive_output must be provided when diagnostics is not supplied.",
         call. = FALSE)
  }

  switch(plot_type,
    ajive_diagnostic    = .plot_ajive_diagnostic(diag, dots),
    rank_threshold      = .plot_rank_threshold(diag, dots),
    bound_distributions = .plot_bound_distributions(diag, dots)
  )
}


# ---------------------------------------------------------------------------
# Internal: .extract_rank_diagnostics
# ---------------------------------------------------------------------------

.extract_rank_diagnostics <- function(ajive_output, format, include_meta) {
  jrs <- ajive_output$joint_rank_sel
  if (is.null(jrs)) {
    stop(paste0(
      "joint_rank_sel not found in ajive_output. ",
      "Ensure the object was created by Rajive() without suppressing rank selection."),
      call. = FALSE)
  }

  obs_svals <- jrs[["obs_svals"]]
  if (is.null(obs_svals) || length(obs_svals) == 0L) {
    stop("Observed singular values not found in joint_rank_sel.", call. = FALSE)
  }
  obs_svals_sq <- obs_svals^2

  joint_rank_estimate <- as.integer(ajive_output$joint_rank)

  # Wedin bound -----------------------------------------------------------
  has_wedin <- !is.null(jrs[["wedin"]])
  if (has_wedin) {
    wedin_cutoff     <- as.numeric(jrs[["wedin"]][["wedin_svsq_threshold"]])
    wedin_samples    <- as.numeric(jrs[["wedin"]][["wedin_samples"]])
    wedin_percentile <- 5  # percentile used by get_joint_scores_robustH
  } else {
    wedin_cutoff     <- NA_real_
    wedin_samples    <- NULL
    wedin_percentile <- NA_real_
  }

  # Random direction bound ------------------------------------------------
  has_random <- !is.null(jrs[["rand_dir"]])
  if (has_random) {
    rand_cutoff      <- as.numeric(jrs[["rand_dir"]][["rand_dir_svsq_threshold"]])
    rand_dir_samples <- as.numeric(jrs[["rand_dir"]][["rand_dir_samples"]])
    rand_percentile  <- 95  # percentile used by get_joint_scores_robustH
  } else {
    rand_cutoff      <- NA_real_
    rand_dir_samples <- NULL
    rand_percentile  <- NA_real_
  }

  if (!has_wedin && !has_random) {
    warning(paste0(
      "Both Wedin and random-direction bounds are absent from joint_rank_sel. ",
      "Diagnostic visualizations will show observed singular values only."),
      call. = FALSE)
  }

  overall_sv_sq_threshold <- jrs[["overall_sv_sq_threshold"]]
  if (is.null(overall_sv_sq_threshold)) overall_sv_sq_threshold <- NA_real_

  cutoff_rule <- if (has_wedin && has_random) {
    "max(wedin, random)"
  } else if (has_wedin) {
    "wedin_only"
  } else if (has_random) {
    "random_only"
  } else {
    "none_available"
  }

  identif_dropped <- jrs[["identif_dropped"]]
  if (is.null(identif_dropped)) identif_dropped <- integer(0L)

  payload <- list(
    obs_svals               = obs_svals,
    obs_svals_sq            = obs_svals_sq,
    joint_rank_estimate     = joint_rank_estimate,
    overall_sv_sq_threshold = overall_sv_sq_threshold,
    wedin_samples           = wedin_samples,
    rand_dir_samples        = rand_dir_samples,
    wedin_cutoff            = wedin_cutoff,
    rand_cutoff             = rand_cutoff,
    wedin_percentile        = wedin_percentile,
    rand_percentile         = rand_percentile,
    identif_dropped         = identif_dropped,
    cutoff_rule             = cutoff_rule,
    has_wedin               = has_wedin,
    has_random              = has_random
  )
  class(payload) <- c("rajive_diagnostics", "list")

  if (format == "wide") return(payload)

  # Long format: one row per observed singular value ----------------------
  n_svals <- length(obs_svals)
  is_joint <- seq_len(n_svals) <= joint_rank_estimate
  classification <- ifelse(
    seq_len(n_svals) %in% identif_dropped, "dropped",
    ifelse(is_joint, "joint", "nonjoint")
  )

  data.frame(
    component_index         = seq_len(n_svals),
    obs_sval                = obs_svals,
    obs_sval_sq             = obs_svals_sq,
    classification          = classification,
    joint_rank_estimate     = joint_rank_estimate,
    overall_sv_sq_threshold = overall_sv_sq_threshold,
    wedin_cutoff            = wedin_cutoff,
    rand_cutoff             = rand_cutoff,
    stringsAsFactors        = FALSE
  )
}


# ---------------------------------------------------------------------------
# Internal: .plot_rank_threshold
# ---------------------------------------------------------------------------

.plot_rank_threshold <- function(diag, dots) {
  theme_fn <- if (!is.null(dots$theme_fn)) dots$theme_fn else ggplot2::theme_bw

  n_svals <- length(diag$obs_svals)
  classification <- ifelse(
    seq_len(n_svals) %in% diag$identif_dropped, "dropped",
    ifelse(seq_len(n_svals) <= diag$joint_rank_estimate, "joint", "nonjoint")
  )

  df <- data.frame(
    idx     = seq_len(n_svals),
    sval_sq = diag$obs_svals_sq,
    class   = factor(classification, levels = c("joint", "nonjoint", "dropped"))
  )

  colors <- c(joint = "black",  nonjoint = "grey60", dropped = "grey30")
  shapes <- c(joint = 16L, nonjoint = 1L,  dropped = 4L)

  has_wedin  <- diag$has_wedin
  has_random <- diag$has_random
  threshold  <- diag$overall_sv_sq_threshold

  subtitle <- if (has_wedin && has_random) {
    sprintf("Joint rank: %d | Threshold: %.4f (%s)",
            diag$joint_rank_estimate, threshold, diag$cutoff_rule)
  } else if (has_wedin) {
    sprintf("Joint rank: %d | Wedin bound only (rand_dir bound unavailable)",
            diag$joint_rank_estimate)
  } else if (has_random) {
    sprintf("Joint rank: %d | Random direction bound only (Wedin bound unavailable)",
            diag$joint_rank_estimate)
  } else {
    sprintf("Joint rank: %d | diagnostic bounds unavailable",
            diag$joint_rank_estimate)
  }

  p <- ggplot2::ggplot(df,
      ggplot2::aes(x = .data$idx, y = .data$sval_sq,
                   color = .data$class, shape = .data$class)) +
    ggplot2::geom_point(size = 3) +
    ggplot2::scale_color_manual(values = colors, name = "Classification",
                                drop = FALSE) +
    ggplot2::scale_shape_manual(values = shapes, name = "Classification",
                                drop = FALSE) +
    ggplot2::labs(
      x        = "Component index",
      y        = expression(Squared~singular~value~(sigma^2)),
      title    = "AJIVE Joint Rank Threshold",
      subtitle = subtitle
    ) +
    theme_fn()

  if (has_wedin) {
    wedin_lw <- if (!has_random || diag$wedin_cutoff >= diag$rand_cutoff) 1.5 else 0.75
    p <- p + ggplot2::geom_hline(
      yintercept = diag$wedin_cutoff,
      color      = "steelblue",
      linetype   = "dashed",
      linewidth  = wedin_lw
    )
  }

  if (has_random) {
    rand_lw <- if (!has_wedin || diag$rand_cutoff >= diag$wedin_cutoff) 1.5 else 0.75
    p <- p + ggplot2::geom_hline(
      yintercept = diag$rand_cutoff,
      color      = "tomato",
      linetype   = "dotted",
      linewidth  = rand_lw
    )
  }

  p
}


# ---------------------------------------------------------------------------
# Internal: .plot_bound_distributions
# ---------------------------------------------------------------------------

.plot_bound_distributions <- function(diag, dots) {
  theme_fn <- if (!is.null(dots$theme_fn)) dots$theme_fn else ggplot2::theme_bw

  if (!is.null(dots$cutoff_quantile)) {
    q <- dots$cutoff_quantile
    if (!is.numeric(q) || length(q) != 1L || q <= 0 || q >= 1) {
      stop("cutoff_quantile must be in (0, 1).", call. = FALSE)
    }
  }

  plots <- list()

  if (diag$has_wedin && !is.null(diag$wedin_samples)) {
    wedin_cutoff <- if (!is.null(dots$cutoff_quantile)) {
      stats::quantile(diag$wedin_samples, dots$cutoff_quantile)
    } else {
      diag$wedin_cutoff
    }
    df_w <- data.frame(sample = diag$wedin_samples)
    plots[["wedin"]] <- ggplot2::ggplot(df_w, ggplot2::aes(x = .data$sample)) +
      ggplot2::geom_histogram(bins = 30L, fill = "steelblue", alpha = 0.7,
                              color = "white") +
      ggplot2::geom_vline(xintercept = wedin_cutoff, color = "steelblue",
                          linewidth = 1.2, linetype = "dashed") +
      ggplot2::labs(
        x     = "Wedin bound samples",
        y     = "Count",
        title = sprintf("Wedin bound (cutoff = %.4f)", wedin_cutoff)
      ) +
      theme_fn()
  }

  if (diag$has_random && !is.null(diag$rand_dir_samples)) {
    rand_cutoff <- if (!is.null(dots$cutoff_quantile)) {
      stats::quantile(diag$rand_dir_samples, dots$cutoff_quantile)
    } else {
      diag$rand_cutoff
    }
    df_r <- data.frame(sample = diag$rand_dir_samples)
    plots[["rand_dir"]] <- ggplot2::ggplot(df_r, ggplot2::aes(x = .data$sample)) +
      ggplot2::geom_histogram(bins = 30L, fill = "tomato", alpha = 0.7,
                              color = "white") +
      ggplot2::geom_vline(xintercept = rand_cutoff, color = "tomato",
                          linewidth = 1.2, linetype = "dashed") +
      ggplot2::labs(
        x     = "Random direction bound samples",
        y     = "Count",
        title = sprintf("Random direction bound (cutoff = %.4f)", rand_cutoff)
      ) +
      theme_fn()
  }

  if (length(plots) == 0L) {
    # No distributions available — annotated empty plot
    return(
      ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0.5, y = 0.5,
                          label  = "diagnostic bounds unavailable",
                          size   = 5, color = "grey50") +
        ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
        ggplot2::theme_void()
    )
  }

  if (length(plots) == 1L) return(plots[[1L]])

  # Both distributions: combine side-by-side
  if (!requireNamespace("patchwork", quietly = TRUE)) {
    stop(paste0(
      "Package 'patchwork' is required to combine both bound-distribution plots. ",
      "Install with: install.packages('patchwork')."),
      call. = FALSE)
  }
  plots[["wedin"]] + plots[["rand_dir"]]
}


# ---------------------------------------------------------------------------
# Internal: .plot_ajive_diagnostic
# ---------------------------------------------------------------------------

.plot_ajive_diagnostic <- function(diag, dots) {
  p_thresh <- .plot_rank_threshold(diag, dots)

  has_wedin  <- diag$has_wedin
  has_random <- diag$has_random

  # No bounds at all: return single panel with annotation already in subtitle
  if (!has_wedin && !has_random) {
    return(p_thresh)
  }

  if (!requireNamespace("patchwork", quietly = TRUE)) {
    stop(paste0(
      "Package 'patchwork' is required for the composite diagnostic panel. ",
      "Install with: install.packages('patchwork')."),
      call. = FALSE)
  }

  # Build individual distribution plots so we can arrange them
  theme_fn <- if (!is.null(dots$theme_fn)) dots$theme_fn else ggplot2::theme_bw

  resolve_cutoff <- function(samples, stored_cutoff, q) {
    if (!is.null(q)) stats::quantile(samples, q) else stored_cutoff
  }
  q <- dots$cutoff_quantile

  dist_plots <- list()

  if (has_wedin && !is.null(diag$wedin_samples)) {
    wc <- resolve_cutoff(diag$wedin_samples, diag$wedin_cutoff, q)
    df_w <- data.frame(sample = diag$wedin_samples)
    dist_plots[["wedin"]] <- ggplot2::ggplot(df_w, ggplot2::aes(x = .data$sample)) +
      ggplot2::geom_histogram(bins = 30L, fill = "steelblue", alpha = 0.7,
                              color = "white") +
      ggplot2::geom_vline(xintercept = wc, color = "steelblue",
                          linewidth = 1.2, linetype = "dashed") +
      ggplot2::labs(x = "Wedin samples", y = "Count",
                    title = sprintf("Wedin (cutoff = %.4f)", wc)) +
      theme_fn()
  }

  if (has_random && !is.null(diag$rand_dir_samples)) {
    rc <- resolve_cutoff(diag$rand_dir_samples, diag$rand_cutoff, q)
    df_r <- data.frame(sample = diag$rand_dir_samples)
    dist_plots[["rand_dir"]] <- ggplot2::ggplot(df_r, ggplot2::aes(x = .data$sample)) +
      ggplot2::geom_histogram(bins = 30L, fill = "tomato", alpha = 0.7,
                              color = "white") +
      ggplot2::geom_vline(xintercept = rc, color = "tomato",
                          linewidth = 1.2, linetype = "dashed") +
      ggplot2::labs(x = "Rand. dir. samples", y = "Count",
                    title = sprintf("Rand. dir. (cutoff = %.4f)", rc)) +
      theme_fn()
  }

  bottom <- if (length(dist_plots) == 2L) {
    dist_plots[["wedin"]] + dist_plots[["rand_dir"]]
  } else {
    dist_plots[[1L]]
  }

  p_thresh / bottom
}


# ---------------------------------------------------------------------------
# associate_components
# ---------------------------------------------------------------------------

#' Associate AJIVE component scores with sample metadata
#'
#' Tests for associations between estimated joint (or individual) component
#' scores from a \code{\link{Rajive}} decomposition and sample-level metadata
#' variables.
#'
#' @section Statistical warnings:
#'
#' \strong{Score estimation error (Finding 4):}
#' Component scores are estimated quantities, not fixed design variables.
#' Estimation error attenuates effect sizes and inflates Type-I error in naive
#' tests. P-values returned by this function do \strong{not} propagate score
#' estimation uncertainty.  Treat results as post-decomposition exploratory
#' associations, not exact fixed-design inference.
#'
#' \strong{Survival split bias (Finding 5):}
#' When \code{mode = "survival"} and a score-split (\code{split = "median"}
#' or \code{split = "tertile"}) is used, the resulting log-rank or Cox p-value
#' is data-adaptive and may be anti-conservative.  Prefer
#' \code{split = "none"} (continuous-score Cox model) for primary inference.
#' Split-based results should be treated as descriptive summaries only.
#'
#' @param ajive_output An object of class \code{"rajive"} (output of
#'   \code{\link{Rajive}}).
#' @param metadata A \code{data.frame} of sample-level metadata; rows must
#'   correspond in order to the samples in \code{ajive_output}.
#' @param scores Optional precomputed scores matrix (samples x components).
#'   When \code{NULL} (default), joint scores are extracted from
#'   \code{ajive_output}.
#' @param mode Character scalar.  One of \code{"continuous"},
#'   \code{"categorical"}, \code{"survival"}, or \code{"batch"}.
#' @param variable Character scalar.  Name of a single column in
#'   \code{metadata} to test.
#' @param variables Character vector.  Names of multiple columns to test.
#'   Ignored when \code{variable} is supplied.
#' @param method Character scalar.  Test method; defaults are Pearson
#'   correlation (\code{"pearson"}) for continuous, Kruskal-Wallis
#'   (\code{"kruskal"}) for categorical, and log-rank (\code{"logrank"})
#'   for survival.
#' @param adjust Character scalar.  P-value adjustment method passed to
#'   \code{\link[stats]{p.adjust}}.  Default \code{"BH"}.
#' @param time_col Character scalar.  Name of the time column in
#'   \code{metadata} (required for \code{mode = "survival"}).
#' @param status_col Character scalar.  Name of the event-status column in
#'   \code{metadata} (required for \code{mode = "survival"}).
#' @param split Character scalar.  Score-split strategy for survival analysis.
#'   One of \code{"none"} (continuous Cox, recommended for primary inference),
#'   \code{"median"}, or \code{"tertile"}.
#' @param type Character scalar.  Source of scores: \code{"joint"} (default)
#'   or \code{"individual"}.
#' @param block Integer or \code{NULL}.  Block index for individual scores.
#' @param component Integer or \code{NULL}.  Restrict analysis to a single
#'   component index.
#' @param ... Reserved for future arguments.
#'
#' @return A \code{data.frame} with one row per variable x component
#'   combination and columns \code{variable}, \code{component}, \code{stat},
#'   \code{p_value}, \code{p_adj}, and \code{method}.
#'
#' @examples
#' \donttest{
#' n   <- 40; pks <- c(30, 20)
#' Y   <- ajive.data.sim(K = 2, rankJ = 2, rankA = c(4, 3),
#'                       n = n, pks = pks, dist.type = 1)
#' fit <- Rajive(Y$sim_data, c(4, 3))
#' meta <- data.frame(group = sample(c("A", "B"), n, replace = TRUE))
#' res  <- associate_components(fit, meta, variable = "group",
#'                              mode = "categorical")
#' }
#'
#' @export
associate_components <- function(ajive_output,
                                 metadata,
                                 scores      = NULL,
                                 mode        = c("continuous", "categorical",
                                                  "survival", "batch"),
                                 variable    = NULL,
                                 variables   = NULL,
                                 method      = NULL,
                                 adjust      = "BH",
                                 time_col    = NULL,
                                 status_col  = NULL,
                                 split       = c("none", "median", "tertile"),
                                 type        = c("joint", "individual"),
                                 block       = NULL,
                                 component   = NULL,
                                 ...) {

  mode  <- match.arg(mode)
  type  <- match.arg(type)
  split <- match.arg(split)

  # --- input validation ---
  if (!inherits(ajive_output, "rajive"))
    stop("`ajive_output` must be an object of class \"rajive\".",
         call. = FALSE)
  if (!is.data.frame(metadata))
    stop("`metadata` must be a data.frame.", call. = FALSE)

  # resolve variable list
  vars <- if (!is.null(variable)) variable else variables
  if (is.null(vars) || length(vars) == 0L)
    stop("Supply at least one variable name via `variable` or `variables`.",
         call. = FALSE)
  missing_vars <- setdiff(vars, names(metadata))
  if (length(missing_vars) > 0L)
    stop("Variables not found in `metadata`: ",
         paste(missing_vars, collapse = ", "), call. = FALSE)

  # --- mandatory inferential warning (#4) ---
  message(
    "[associate_components] NOTE: Component scores are estimated quantities. ",
    "Score estimation error is NOT propagated into the returned p-values. ",
    "Treat results as post-decomposition exploratory associations, not exact ",
    "fixed-design inference (StatisticalAudits.md, Finding 4)."
  )

  # --- survival split bias warning (#5) ---
  if (mode == "survival" && split != "none") {
    message(
      "[associate_components] WARNING: Split-based survival inference ",
      "(split = \"", split, "\") is data-adaptive and may be anti-conservative. ",
      "Use split = \"none\" (continuous-score Cox model) for primary inference. ",
      "Split-based results should be labeled as descriptive summaries ",
      "(StatisticalAudits.md, Finding 5)."
    )
  }

  # --- extract scores ---
  if (is.null(scores)) {
    if (type == "joint") {
      sc <- ajive_output$joint_scores
      if (is.null(sc))
        stop("Joint scores not found in `ajive_output`. ",
             "Was `Rajive()` run with a positive joint rank?", call. = FALSE)
    } else {
      if (is.null(block))
        stop("`block` must be specified when `type = \"individual\"`.",
             call. = FALSE)
      sc <- ajive_output$block_decomps[[3L * (as.integer(block) - 1L) + 1L]]$u
      if (is.null(sc))
        stop("Individual scores not found for block ", block, ".", call. = FALSE)
    }
    scores <- sc
  }

  if (is.vector(scores))
    scores <- matrix(scores, ncol = 1L)

  n_comp <- ncol(scores)
  comps  <- if (!is.null(component)) component else seq_len(n_comp)

  if (nrow(scores) != nrow(metadata))
    stop("`metadata` must have the same number of rows as samples in scores (",
         nrow(scores), ").", call. = FALSE)

  # --- run per variable x component ---
  rows <- vector("list", length(vars) * length(comps))
  idx  <- 1L

  for (v in vars) {
    y <- metadata[[v]]
    for (j in comps) {
      x <- scores[, j]
      res_j <- .associate_one(x, y, mode, method, time_col, status_col,
                              split, metadata)
      rows[[idx]] <- data.frame(
        variable  = v,
        component = j,
        stat      = res_j$stat,
        p_value   = res_j$p_value,
        method    = res_j$method,
        stringsAsFactors = FALSE
      )
      idx <- idx + 1L
    }
  }

  out <- do.call(rbind, rows)
  out$p_adj <- stats::p.adjust(out$p_value, method = adjust)
  out[, c("variable", "component", "stat", "p_value", "p_adj", "method")]
}


# Internal: .associate_one — single variable x component test dispatch
.associate_one <- function(scores_j, y, mode, method, time_col, status_col,
                           split, metadata) {
  switch(mode,

    continuous = {
      meth <- if (!is.null(method)) method else "pearson"
      ct   <- suppressWarnings(
        stats::cor.test(scores_j, as.numeric(y), method = meth)
      )
      list(stat = unname(ct$estimate), p_value = ct$p.value, method = meth)
    },

    categorical = {
      meth <- if (!is.null(method)) method else "kruskal"
      kt   <- stats::kruskal.test(scores_j ~ factor(y))
      list(stat = unname(kt$statistic), p_value = kt$p.value, method = meth)
    },

    survival = {
      if (is.null(time_col) || is.null(status_col))
        stop("`time_col` and `status_col` must be supplied for ",
             "mode = \"survival\".", call. = FALSE)
      # Continuous Cox (primary; split applied below if requested)
      t_vec <- metadata[[time_col]]
      s_vec <- metadata[[status_col]]
      if (!requireNamespace("survival", quietly = TRUE))
        stop("Package 'survival' is required for mode = \"survival\".",
             call. = FALSE)
      surv_obj <- survival::Surv(as.numeric(t_vec), as.logical(s_vec))
      if (split == "none") {
        fit <- survival::coxph(surv_obj ~ scores_j)
        sm  <- summary(fit)
        list(stat = sm$coefficients[1L, "z"],
             p_value = sm$coefficients[1L, "Pr(>|z|)"],
             method = "cox_continuous")
      } else {
        grp <- if (split == "median") {
          ifelse(scores_j >= stats::median(scores_j), "high", "low")
        } else {
          qs  <- stats::quantile(scores_j, c(1/3, 2/3))
          cut(scores_j, breaks = c(-Inf, qs, Inf),
              labels = c("low", "mid", "high"))
        }
        lr <- survival::survdiff(surv_obj ~ grp)
        p  <- 1 - stats::pchisq(lr$chisq, df = length(unique(grp)) - 1L)
        list(stat = lr$chisq, p_value = p,
             method = paste0("logrank_", split))
      }
    },

    batch = {
      meth <- if (!is.null(method)) method else "kruskal"
      kt   <- stats::kruskal.test(scores_j ~ factor(y))
      list(stat = unname(kt$statistic), p_value = kt$p.value, method = meth)
    }
  )
}


# ---------------------------------------------------------------------------
# assess_stability
# ---------------------------------------------------------------------------

#' Assess stability of AJIVE decomposition via bootstrap resampling
#'
#' Evaluates the stability of the estimated joint rank or block loadings via
#' bootstrap resampling of the sample dimension.
#'
#' @section Procrustes alignment for loading stability (Finding 3):
#' When \code{target = "loadings"}, bootstrap loading matrices are aligned to
#' the reference (full-data) loading matrix using orthogonal Procrustes
#' rotation before any variability summary is computed.  Raw bootstrap loading
#' variation is dominated by rotational indeterminacy and is not interpretable
#' without alignment.  All returned stability summaries are computed
#' \strong{after} Procrustes alignment (StatisticalAudits.md, Finding 3).
#'
#' @param ajive_output An object of class \code{"rajive"} (output of
#'   \code{\link{Rajive}}).  Required for \code{target = "loadings"} and
#'   \code{target = "components"}.
#' @param blocks List of data matrices (same list passed to
#'   \code{\link{Rajive}}).
#' @param initial_signal_ranks Integer vector of initial signal ranks for each
#'   block.
#' @param target Character scalar.  One of \code{"joint_rank"},
#'   \code{"loadings"}, or \code{"components"}.
#' @param method Character scalar.  \code{"bootstrap"} (default) or
#'   \code{"permutation"}.
#' @param B Positive integer.  Number of bootstrap replicates.  Default 100.
#' @param n_perm Positive integer.  Number of permutations (only used when
#'   \code{method = "permutation"}).  Default 100.
#' @param sample_frac Numeric in (0, 1].  Fraction of samples to draw in each
#'   bootstrap replicate.  Default 0.8.
#' @param num_cores Positive integer.  Number of cores for parallel execution.
#'   Default 1 (no parallelism).
#' @param ... Reserved for future arguments.
#'
#' @return A named list whose structure depends on \code{target}:
#' \describe{
#'   \item{\code{"joint_rank"}}{A list with fields \code{rank_distribution}
#'     (integer vector of length \code{B}), \code{rank_table} (frequency
#'     table), and \code{observed_rank} (integer).}
#'   \item{\code{"loadings"}}{A list with one element per block.  Each element
#'     contains \code{mean_loading} (aligned mean loading matrix),
#'     \code{sd_loading} (element-wise standard deviation after alignment), and
#'     \code{cos_similarity} (vector of mean cosine similarities per
#'     component).  All summaries are computed after orthogonal Procrustes
#'     alignment.}
#' }
#'
#' @examples
#' \donttest{
#' n   <- 40; pks <- c(30, 20)
#' Y   <- ajive.data.sim(K = 2, rankJ = 2, rankA = c(4, 3),
#'                       n = n, pks = pks, dist.type = 1)
#' fit <- Rajive(Y$sim_data, c(4, 3))
#' stab <- assess_stability(fit, Y$sim_data, c(4, 3),
#'                          target = "joint_rank", B = 50)
#' stab$rank_table
#' }
#'
#' @export
assess_stability <- function(ajive_output = NULL,
                             blocks,
                             initial_signal_ranks,
                             target      = c("joint_rank", "loadings",
                                              "components"),
                             method      = c("bootstrap", "permutation"),
                             B           = 100L,
                             n_perm      = 100L,
                             sample_frac = 0.8,
                             num_cores   = 1L,
                             ...) {

  target <- match.arg(target)
  method <- match.arg(method)

  if (!is.list(blocks) || length(blocks) == 0L)
    stop("`blocks` must be a non-empty list of matrices.", call. = FALSE)
  if (length(initial_signal_ranks) != length(blocks))
    stop("`initial_signal_ranks` must have the same length as `blocks`.",
         call. = FALSE)
  B <- as.integer(B)
  if (B < 2L)
    stop("`B` must be at least 2.", call. = FALSE)
  if (sample_frac <= 0 || sample_frac > 1)
    stop("`sample_frac` must be in (0, 1].", call. = FALSE)

  n_samples <- nrow(blocks[[1L]])

  switch(target,

    joint_rank = {
      rank_draws <- integer(B)
      for (b in seq_len(B)) {
        idx    <- sample.int(n_samples, size = max(2L, floor(sample_frac * n_samples)),
                             replace = TRUE)
        b_list <- lapply(blocks, function(X) X[idx, , drop = FALSE])
        fit_b  <- tryCatch(
          Rajive(b_list, initial_signal_ranks),
          error = function(e) NULL
        )
        rank_draws[b] <- if (is.null(fit_b)) NA_integer_ else fit_b$joint_rank
      }
      list(
        rank_distribution = rank_draws,
        rank_table        = table(rank_draws, useNA = "ifany"),
        observed_rank     = if (!is.null(ajive_output)) ajive_output$joint_rank else NA_integer_
      )
    },

    loadings = {
      if (is.null(ajive_output))
        stop("`ajive_output` must be supplied for target = \"loadings\".",
             call. = FALSE)
      if (!inherits(ajive_output, "rajive"))
        stop("`ajive_output` must be of class \"rajive\".", call. = FALSE)

      K          <- length(blocks)
      joint_rank <- ajive_output$joint_rank
      if (joint_rank == 0L)
        stop("Cannot assess loading stability when joint_rank = 0.", call. = FALSE)

      # Reference loadings: list of K matrices (features x joint_rank)
      # block_decomps layout: individual at 3k-2, joint at 3k-1, noise at 3k
      # $v = features x rank (loadings); $u = samples x rank (scores)
      ref_loadings <- lapply(seq_len(K), function(k) {
        ajive_output$block_decomps[[3L * (k - 1L) + 2L]]$v
      })

      # Bootstrap loading draws: list-of-K, each element is an array
      # (features x joint_rank x B)
      boot_arrays <- lapply(seq_len(K), function(k) {
        array(NA_real_,
              dim = c(nrow(ref_loadings[[k]]), joint_rank, B))
      })

      for (b in seq_len(B)) {
        idx    <- sample.int(n_samples, size = max(2L, floor(sample_frac * n_samples)),
                             replace = TRUE)
        b_list <- lapply(blocks, function(X) X[idx, , drop = FALSE])
        fit_b  <- tryCatch(
          Rajive(b_list, initial_signal_ranks),
          error = function(e) NULL
        )
        if (is.null(fit_b) || fit_b$joint_rank < joint_rank) next

        for (k in seq_len(K)) {
          L_b <- fit_b$block_decomps[[3L * (k - 1L) + 2L]]$v
          # Procrustes-align L_b to reference (Finding #3)
          Q         <- .procrustes_align(ref_loadings[[k]], L_b)
          L_aligned <- L_b %*% Q
          boot_arrays[[k]][, , b] <- L_aligned
        }
      }

      # Summarise across bootstrap replicates
      result <- vector("list", K)
      names(result) <- names(blocks)
      for (k in seq_len(K)) {
        arr         <- boot_arrays[[k]]
        mean_load   <- apply(arr, c(1L, 2L), mean, na.rm = TRUE)
        sd_load     <- apply(arr, c(1L, 2L), stats::sd, na.rm = TRUE)
        ref         <- ref_loadings[[k]]
        cos_sim     <- vapply(seq_len(joint_rank), function(j) {
          ref_j  <- ref[, j]
          mn_j   <- mean_load[, j]
          sum(ref_j * mn_j) /
            (sqrt(sum(ref_j^2)) * sqrt(sum(mn_j^2)) + .Machine$double.eps)
        }, numeric(1L))
        result[[k]] <- list(
          mean_loading  = mean_load,
          sd_loading    = sd_load,
          cos_similarity = cos_sim
        )
      }
      result
    },

    components = {
      stop("target = \"components\" is not yet implemented.", call. = FALSE)
    }
  )
}


# ---------------------------------------------------------------------------
# Internal: orthogonal Procrustes alignment
# ---------------------------------------------------------------------------

# .procrustes_align(A, B) returns an orthogonal rotation matrix Q such that
# B %*% Q is as close as possible to A in Frobenius norm.
# Solution: Q = V %*% t(U) where svd(t(A) %*% B) = U D V'.
.procrustes_align <- function(A, B) {
  P     <- crossprod(A, B)          # t(A) %*% B
  sv    <- svd(P)
  sv$v %*% t(sv$u)
}


# ---------------------------------------------------------------------------
# rank_features
# ---------------------------------------------------------------------------

#' Rank and summarize features from a Rajive decomposition
#'
#' Returns a tidy \code{data.frame} of features ranked by their loading,
#' proportional contribution, pairwise feature-set overlap, or jackstraw
#' significance, depending on \code{mode}.
#'
#' @param ajive_output An object of class \code{"rajive"} (output of
#'   \code{\link{Rajive}}).  Required for \code{mode} in
#'   \code{"top_loadings"}, \code{"contribution"}, and \code{"overlap"}.
#'   May be \code{NULL} for \code{mode = "significant"}.
#' @param blocks Not currently used; reserved for future feature-name lookup
#'   against the original data matrices.
#' @param jackstraw_result An object of class \code{"jackstraw_rajive"} (output
#'   of \code{\link{jackstraw_rajive}}).  Required for
#'   \code{mode = "significant"}.
#' @param mode Character scalar.  One of:
#'   \describe{
#'     \item{\code{"top_loadings"}}{Return the top \code{n} features per
#'       block \eqn{\times} component by absolute loading.}
#'     \item{\code{"contribution"}}{Return the top \code{n} features per
#'       block \eqn{\times} component by their normalized contribution score.
#'       For \code{method = "abs_loading"}: \eqn{|w_i| / \sum |w_j|}.
#'       For \code{method = "variance_contrib"}:
#'       \eqn{w_i^2 / \sum w_j^2}.}
#'     \item{\code{"overlap"}}{Compute pairwise Jaccard or overlap-coefficient
#'       between the top-\code{n} feature sets of each pair of blocks for each
#'       requested component.}
#'     \item{\code{"significant"}}{Return all features from a jackstraw result
#'       with their p-values and significance calls, sorted by block, component,
#'       and p-value.}
#'   }
#' @param type Character.  \code{"joint"} (default) or \code{"individual"}.
#'   Selects which loading matrix is used.
#' @param block Integer or \code{NULL}.  Block index to restrict results to.
#'   When \code{NULL} (default), all blocks are included.
#' @param component Integer or \code{NULL}.  Component index to restrict
#'   results to.  When \code{NULL} (default), all components are included.
#' @param n Integer.  Number of top features returned per block
#'   \eqn{\times} component (for \code{mode} in \code{"top_loadings"},
#'   \code{"contribution"}).  Also the feature-set size used in
#'   \code{mode = "overlap"}.  Default 20.
#' @param signed Logical.  When \code{TRUE} (default), the \code{loading}
#'   column retains the sign of the original loading.  When \code{FALSE},
#'   the absolute value is stored.  Ignored for \code{mode} in
#'   \code{"overlap"} and \code{"significant"}.
#' @param method Character or \code{NULL}.  Scoring or overlap method.
#'   For \code{mode} in \code{"top_loadings"} and \code{"contribution"}:
#'   \code{"abs_loading"} (default) or \code{"variance_contrib"}.
#'   For \code{mode = "overlap"}: \code{"jaccard"} (default) or
#'   \code{"overlap_coef"}.
#'   Ignored for \code{mode = "significant"}.
#' @param ... Reserved for future arguments.
#'
#' @return A \code{data.frame}.  Column set depends on \code{mode}:
#'   \describe{
#'     \item{\code{"top_loadings"}}{
#'       \code{block}, \code{component}, \code{type},
#'       \code{feature_index}, \code{feature_name},
#'       \code{loading}, \code{abs_loading}, \code{rank}.}
#'     \item{\code{"contribution"}}{
#'       Same as \code{"top_loadings"} plus \code{contribution}.}
#'     \item{\code{"overlap"}}{
#'       \code{component}, \code{type}, \code{block_i}, \code{block_j},
#'       \code{top_n}, \code{method}, \code{n_intersect},
#'       \code{overlap_score}.}
#'     \item{\code{"significant"}}{
#'       \code{block}, \code{component}, \code{feature_index},
#'       \code{p_value}, \code{p_adj}, \code{significant}.}
#'   }
#'   Returns \code{NULL} (with a message) when no valid block/component
#'   combinations are found.
#'
#' @examples
#' \donttest{
#' n <- 40; pks <- c(30, 20)
#' Y   <- ajive.data.sim(K = 2, rankJ = 2, rankA = c(4, 3),
#'                       n = n, pks = pks, dist.type = 1)
#' fit <- Rajive(Y$sim_data, c(4, 3))
#'
#' # Top 10 joint loadings across all blocks
#' rank_features(fit, mode = "top_loadings", type = "joint", n = 10)
#'
#' # Proportional contribution (variance) for individual components
#' rank_features(fit, mode = "contribution", type = "individual",
#'               block = 1, component = 1, method = "variance_contrib")
#'
#' # Pairwise feature-set overlap across all blocks for joint component 1
#' rank_features(fit, mode = "overlap", type = "joint", component = 1, n = 15)
#'
#' # Significant jackstraw features
#' jsr <- jackstraw_rajive(fit, Y$sim_data)
#' rank_features(jackstraw_result = jsr, mode = "significant", block = 1)
#' }
#'
#' @export
rank_features <- function(ajive_output    = NULL,
                          blocks          = NULL,
                          jackstraw_result = NULL,
                          mode      = c("top_loadings", "contribution",
                                        "overlap", "significant"),
                          type      = c("joint", "individual"),
                          block     = NULL,
                          component = NULL,
                          n         = 20L,
                          signed    = TRUE,
                          method    = NULL,
                          ...) {
  mode <- match.arg(mode)
  type <- match.arg(type)
  n    <- as.integer(n)
  if (n < 1L) stop("`n` must be a positive integer.", call. = FALSE)

  method <- .rf_resolve_method(method, mode)

  switch(mode,
    top_loadings = {
      if (!inherits(ajive_output, "rajive"))
        stop("`ajive_output` must be an object of class \"rajive\".", call. = FALSE)
      .rf_loading_df(ajive_output, type, block, component, n, signed, method,
                     add_contribution = FALSE)
    },
    contribution = {
      if (!inherits(ajive_output, "rajive"))
        stop("`ajive_output` must be an object of class \"rajive\".", call. = FALSE)
      .rf_loading_df(ajive_output, type, block, component, n, signed, method,
                     add_contribution = TRUE)
    },
    overlap = {
      if (!inherits(ajive_output, "rajive"))
        stop("`ajive_output` must be an object of class \"rajive\".", call. = FALSE)
      .rf_overlap(ajive_output, type, block, component, n, method)
    },
    significant = {
      .rf_significant(jackstraw_result, block, component)
    }
  )
}


# ---------------------------------------------------------------------------
# Aliases (thin wrappers)
# ---------------------------------------------------------------------------

#' @rdname rank_features
#' @export
get_top_loadings <- function(ajive_output, block = NULL, component = NULL,
                             type = c("joint", "individual"),
                             n = 20L, signed = TRUE) {
  rank_features(ajive_output, mode = "top_loadings", type = match.arg(type),
                block = block, component = component, n = n, signed = signed)
}

#' @rdname rank_features
#' @export
get_feature_contributions <- function(ajive_output, block = NULL, component = NULL,
                                      type   = c("joint", "individual"),
                                      method = c("abs_loading",
                                                 "variance_contrib")) {
  rank_features(ajive_output, mode = "contribution", type = match.arg(type),
                block = block, component = component,
                method = match.arg(method))
}

#' @rdname rank_features
#' @export
compare_feature_sets_across_blocks <- function(ajive_output, component = NULL,
                                               type   = c("joint", "individual"),
                                               n      = 50L,
                                               method = c("jaccard",
                                                          "overlap_coef")) {
  rank_features(ajive_output, mode = "overlap", type = match.arg(type),
                component = component, n = n, method = match.arg(method))
}

#' @rdname rank_features
#' @export
summarize_significant_vars <- function(jackstraw_result, block = NULL,
                                       component = NULL, top_n = NULL) {
  out <- rank_features(jackstraw_result = jackstraw_result,
                       mode = "significant", block = block,
                       component = component)
  if (!is.null(top_n) && !is.null(out)) {
    grp <- paste(out$block, out$component)
    out <- do.call(rbind, lapply(split(out, grp), function(df) {
      df <- df[order(df$p_value), ]
      head(df, as.integer(top_n))
    }))
    rownames(out) <- NULL
  }
  out
}


# ---------------------------------------------------------------------------
# Internal: rank_features workers
# ---------------------------------------------------------------------------

.rf_resolve_method <- function(method, mode) {
  if (is.null(method)) {
    return(switch(mode,
      top_loadings = "abs_loading",
      contribution = "abs_loading",
      overlap      = "jaccard",
      significant  = NULL
    ))
  }
  method <- match.arg(method, c("abs_loading", "variance_contrib",
                                "jaccard", "overlap_coef"))
  if (mode %in% c("top_loadings", "contribution") &&
      method %in% c("jaccard", "overlap_coef"))
    stop(sprintf(
      "method = '%s' is not valid for mode = '%s'. Use 'abs_loading' or 'variance_contrib'.",
      method, mode), call. = FALSE)
  if (mode == "overlap" && method %in% c("abs_loading", "variance_contrib"))
    stop(sprintf(
      "method = '%s' is not valid for mode = 'overlap'. Use 'jaccard' or 'overlap_coef'.",
      method), call. = FALSE)
  method
}

# Returns loading matrix (features x components) for block k.
# Individual: index 3*(k-1)+1; joint: index 3*(k-1)+2.
.rf_get_loadings <- function(ajive_output, k, type) {
  k   <- as.integer(k)
  idx <- if (type == "individual") 3L * (k - 1L) + 1L else 3L * (k - 1L) + 2L
  bd  <- ajive_output$block_decomps[[idx]]
  if (is.null(bd) || is.null(bd$v) || ncol(bd$v) == 0L) return(NULL)
  bd$v
}

.rf_loading_df <- function(ajive_output, type, block, component, n,
                           signed, method, add_contribution) {
  K        <- length(ajive_output$block_decomps) %/% 3L
  blocks_k <- if (is.null(block)) seq_len(K) else as.integer(block)

  rows <- list()
  for (k in blocks_k) {
    mat <- .rf_get_loadings(ajive_output, k, type)
    if (is.null(mat)) next
    n_comp     <- ncol(mat)
    feat_names <- rownames(mat)
    comps      <- if (is.null(component)) seq_len(n_comp) else as.integer(component)

    for (j in comps) {
      if (j > n_comp) next
      load_j  <- mat[, j]
      score_j <- if (method == "variance_contrib") {
        ss <- sum(load_j^2)
        if (ss == 0) rep(0, length(load_j)) else load_j^2 / ss
      } else {
        s1 <- sum(abs(load_j))
        if (s1 == 0) rep(0, length(load_j)) else abs(load_j) / s1
      }
      n_take <- min(n, length(load_j))
      ord    <- order(score_j, decreasing = TRUE)[seq_len(n_take)]

      row_df <- data.frame(
        block         = k,
        component     = j,
        type          = type,
        feature_index = ord,
        feature_name  = if (!is.null(feat_names)) feat_names[ord] else NA_character_,
        loading       = if (signed) load_j[ord] else abs(load_j[ord]),
        abs_loading   = abs(load_j[ord]),
        stringsAsFactors = FALSE
      )
      if (add_contribution) row_df$contribution <- score_j[ord]
      row_df$rank <- seq_len(n_take)
      rows[[length(rows) + 1L]] <- row_df
    }
  }

  if (length(rows) == 0L) {
    message("No valid block/component combinations found. Returning NULL.")
    return(NULL)
  }
  do.call(rbind, rows)
}

.rf_overlap <- function(ajive_output, type, block, component, n, method) {
  K        <- length(ajive_output$block_decomps) %/% 3L
  blocks_k <- if (is.null(block)) seq_len(K) else as.integer(block)
  if (length(blocks_k) < 2L)
    stop("mode = 'overlap' requires at least two blocks.", call. = FALSE)

  # use first valid block to infer component count
  ref_mat <- NULL
  for (k in blocks_k) {
    ref_mat <- .rf_get_loadings(ajive_output, k, type)
    if (!is.null(ref_mat)) break
  }
  if (is.null(ref_mat))
    stop("No valid loading matrices found for the requested blocks.", call. = FALSE)
  n_comp <- ncol(ref_mat)
  comps  <- if (is.null(component)) seq_len(n_comp) else as.integer(component)

  rows <- list()
  for (j in comps) {
    feat_sets <- lapply(blocks_k, function(k) {
      mat <- .rf_get_loadings(ajive_output, k, type)
      if (is.null(mat) || j > ncol(mat)) return(integer(0L))
      n_take <- min(n, nrow(mat))
      order(abs(mat[, j]), decreasing = TRUE)[seq_len(n_take)]
    })

    nb <- length(blocks_k)
    for (i in seq_len(nb - 1L)) {
      for (jj in (i + 1L):nb) {
        A       <- feat_sets[[i]]
        B       <- feat_sets[[jj]]
        n_inter <- length(intersect(A, B))
        n_union <- length(union(A, B))
        score   <- if (method == "jaccard") {
          if (n_union == 0L) NA_real_ else n_inter / n_union
        } else {
          denom <- min(length(A), length(B))
          if (denom == 0L) NA_real_ else n_inter / denom
        }
        rows[[length(rows) + 1L]] <- data.frame(
          component     = j,
          type          = type,
          block_i       = blocks_k[i],
          block_j       = blocks_k[jj],
          top_n         = n,
          method        = method,
          n_intersect   = n_inter,
          overlap_score = score,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(rows) == 0L) return(NULL)
  do.call(rbind, rows)
}

.rf_significant <- function(jackstraw_result, block, component) {
  if (is.null(jackstraw_result))
    stop("`jackstraw_result` must be provided for mode = \"significant\".",
         call. = FALSE)
  if (!inherits(jackstraw_result, "jackstraw_rajive"))
    stop("`jackstraw_result` must be of class \"jackstraw_rajive\".",
         call. = FALSE)

  block_names <- names(jackstraw_result)
  use_blocks  <- if (!is.null(block)) {
    paste0("block", as.integer(block))
  } else {
    block_names
  }

  rows <- list()
  for (bn in use_blocks) {
    if (!bn %in% block_names) next
    blk        <- jackstraw_result[[bn]]
    comp_names <- names(blk)
    use_comps  <- if (!is.null(component)) {
      paste0("comp", as.integer(component))
    } else {
      comp_names
    }
    block_idx <- as.integer(sub("^block", "", bn))

    for (cn in use_comps) {
      if (!cn %in% comp_names) next
      comp_idx <- as.integer(sub("^comp", "", cn))
      cdata    <- blk[[cn]]
      n_feat   <- length(cdata$p_values)

      rows[[length(rows) + 1L]] <- data.frame(
        block         = block_idx,
        component     = comp_idx,
        feature_index = seq_len(n_feat),
        p_value       = cdata$p_values,
        p_adj         = cdata$p_adj,
        significant   = cdata$significant,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0L) {
    message("No valid block/component combinations found. Returning NULL.")
    return(NULL)
  }
  out <- do.call(rbind, rows)
  out[order(out$block, out$component, out$p_value), ]
}

