
#' Fit a tuned Virtual Twins model
#'
#' \code{tunevt} fits a Virtual Twins model to estimate factors and subgroups
#' associated with differential treatment effects while controlling the Type I
#' error rate of falsely detecting at least one heterogeneous effect when the
#' treatment effect is uniform across the study population.
#'
#' Virtual Twins is a two-step approach to detecting differential treatment
#' effects. Subjects' conditional average treatment effects (CATEs) are first
#' estimated in Step 1 using a flexible model. Then, a simple and interpretable
#' model is fit in Step 2 to model either (1) the expected value of these
#' estimated CATEs if \code{step2} is equal to "\code{lasso}", "\code{rtree}",
#' or "\code{ctree}" or (2) the probability that the CATE is greater than a
#' specified \code{threshold} if \code{step2} is equal to "\code{classtree}".
#'
#' The Step 2 model is dependent on some tuning parameter. This parameter is
#' selected to control the Type I error rate by permuting the data under the
#' null hypothesis of a constant treatment effect and identifying the minimal
#' null penalty parameter (MNPP), which is the smallest penalty parameter that
#' yields a Step 2 model with no covariate effects. The \code{1-alpha0} quantile
#' of the distribution of is then used to fit the Step 2 model on the original
#' data.
#'
#' @param data a data frame containing a response, binary treatment indicators,
#'   and covariates.
#' @param Trt a string specifying the name of the column of \code{data}
#'   contains the treatment indicators.
#' @param Y a string specifying the name of the column of \code{data}
#'   contains the response.
#' @param step1 character strings specifying the Step 1 model. Supports
#'   either "\code{lasso}", "\code{mars}", "\code{randomforest}", or
#'   "\code{superlearner}".
#' @param step2 a character string specifying the Step 2 model. Supports
#'   "\code{lasso}", "\code{rtree}",  "\code{classtree}", or "\code{ctree}".
#' @param alpha0 the nominal Type I error rate.
#' @param p_reps the number of permutations to run.
#' @param threshold for "\code{step2 = 'classtree'}" only. The value against
#'   which to test if the estimated individual treatment effect from Step 1 is
#'   higher (TRUE) or lower (FALSE).
#' @param keepz logical. Should the estimated CATE from Step 1 be returned?
#' @param parallel Should the loop over replications be parallelized? If
#'   \code{FALSE}, then no, if \code{TRUE}, then yes.
#'   Note that running in parallel requires a _parallel backend_ that must be
#'   registered before performing the computation.
#'   See the \code{\link[foreach]{foreach}} documentation for more details.
#' @param ... additional arguments to the Step 1 model call.
#'
#' @return An object of class \code{"tunevt"}.
#'
#'   An object of class \code{"tunevt"} is a list containing at least the
#'   following components:
#'     \item{call}{the matched call}
#'     \item{vtmod}{the model estimated by the given \code{step2} procedure fit
#'       with the permuted tuning parameter for the estimated CATEs from the
#'       \code{step1} model. See \code{\link{vt2_lasso}},
#'       \code{\link{vt2_rtree}}, or \code{\link{vt2_ctree}} for specifics.}
#'     \item{mnpp}{the MNPP for the estimated CATEs from Step 1.}
#'     \item{theta_null}{a vector of the MNPPs from each permutation under
#'       the null hypothesis.}
#'     \item{pvalue}{the probability of observing a MNPP as or more extreme
#'       as the observed MNPP under the null hypothesis of no effect
#'       heterogeneity.}
#'     \item{z}{if \code{keepz = TRUE}, the estimated CATEs from the
#'       \code{step1} model.}
#' @importFrom Rdpack reprompt
#' @references{
#'
#'   \insertRef{foster_subgroup_2011}{tehtuner}
#'
#'   \insertRef{wolf_permutation_2022}{tehtuner}
#'
#'   \insertRef{deng_practical_2023}{tehtuner}
#'
#' }
#'
#' @examples
#' data(tehtuner_example)
#' # Low p_reps for example use only
#' tunevt(
#'   tehtuner_example, step1 = "lasso", step2 = "rtree",
#'   alpha0 = 0.2, p_reps = 5
#' )
#'
#' @export
tunevt <- function(
    data, Y = "Y", Trt = "Trt", step1 = "randomforest", step2 = "rtree",
    alpha0, p_reps, threshold = NA, keepz = FALSE, parallel = FALSE, ...)
{

  cl <- match.call()

  # Check inputs
  validate_Y(data = data, Y = Y)
  validate_Trt(data = data, Trt = Trt)
  validate_alpha0(data = data, alpha0 = alpha0)
  validate_p_reps(data = data, p_reps = p_reps)

  # Subset data by treatment indicator for Step 1
  d0 <- subset_trt(data, value = 0, Trt = Trt)
  d1 <- subset_trt(data, value = 1, Trt = Trt)

  # Estimate marginal average treatment effect
  zbar <- mean(d1[, Y]) - mean(d0[, Y])

  # Permutation to get the null distribution of the MNPP
  theta <- tune_theta(data = data, Trt = Trt, Y = Y, zbar = zbar,
                      step1 = step1, step2 = step2,
                      alpha0 = alpha0, p_reps = p_reps,
                      parallel = parallel, threshold = threshold,
                      ...)

  # Fit Virtual Twins
  # Step 1
  vt1 <- get_vt1(step1)
  z <- vt1(data, Trt = Trt, Y = Y, ...)

  # Step 2
  vt2 <- get_vt2(step2)
  if (step2 == "classtree") {
    mod <- vt2(z, data, Trt = Trt, Y = Y, theta = theta$theta, threshold = threshold)
  } else {
    mod <- vt2(z, data, Trt = Trt, Y = Y, theta = theta$theta)
  }

  # MNPP for the original data
  mnpp <- get_mnpp(z = z, data = data, step2 = step2, Trt = Trt, Y = Y, threshold = threshold)

  # P-value:
  pvalue <- mean(theta$theta_grid > mnpp)

  re <- list(
    vtmod = mod,
    theta_null = theta$theta_grid,
    mnpp = mnpp,
    pvalue = pvalue
  )

  re$call <- cl

  if ( keepz ) {
    re$z <- z
  }

  class(re) <- "tunevt"

  return(re)

}

#' Print an object of class tunevt
#'
#' Prints a Virtual Twins model for the conditional average treatment effect
#' with a tuned Step 2 model.
#'
#' @method print tunevt
#'
#' @param x an object of class \code{tunevt}
#' @param digits the number of significant digits to use when printing.
#' @param ... further arguments passed to or from other methods.
#'
#' @export
#' @inherit tunevt return
print.tunevt <- function(x, digits = max(3L, getOption("digits") - 3L), ...) {

  cat("Call:\n", paste(deparse(x$call),
                         sep = "\n",
                         collapse = "\n"
  ), "\n", sep = "")

  cat("\nStep 2", paste0('"', x$call$step2, '"'), "model:\n")
  if (x$call$step2 == "lasso") {
    print(coef(x$vtmod), ...)
  } else {
    print(x$vtmod, ...)
  }
  cat("\n")

  quant <- 1 - x$call$alpha0
  quantval <- unname(
    quantile(x$theta_null, probs = quant, na.rm = TRUE, type = 2))

  cat(
    "Approximate ",
    trimws(formatC(quant, digits)), " quantile of the MNPP null distribution: ",
    formatC(quantval, digits),
    "\nObserved MNPP: ", formatC(x$mnpp, digits),
    ",\tp-value: ", format.pval(x$pvalue),
    sep = ""
    )
  cat("\n")
  invisible(x)
}
