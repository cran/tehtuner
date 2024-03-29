% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/step_2.R
\name{get_vt2}
\alias{get_vt2}
\title{Get the appropriate Step 2 estimation function associated with a method}
\usage{
get_vt2(step2)
}
\arguments{
\item{step2}{a character string specifying the Step 2 model. Supports
"\code{lasso}", "\code{rtree}",  "\code{classtree}", or "\code{ctree}".}
}
\value{
a function that fits a model for the CATE through Step 2 of Virtual
Twins
}
\description{
Get the appropriate Step 2 estimation function associated with a method
}
