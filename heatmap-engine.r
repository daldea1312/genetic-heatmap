#!/usr/bin/env Rscript

#===============================================================================
# TITLE    : heatmap-generator.r
# ABSTRACT : An R script that creates gene transcription and gene binding
#            heatmaps from CSV files
#
# AUTHOR   : Dennis Aldea <dennis.aldea@gmail.com>
# DATE     : 2017-06-28
#
# LICENCE  : MIT <https://opensource.org/licenses/MIT>
#-------------------------------------------------------------------------------
# USAGE:
#
#     ./heatmap-generator.r CSV_PATH INCLUDE_ZEROS TRANSCRIPTION_MIN
#         TRANSCRIPTION_MAX BINDING_MAX TRANSCRIPTION_PATH BINDING_PATH
#
# ARGUMENTS:
#
#     CSV_PATH           : filepath of the CSV file containing gene
#                          transcription and gene binding data
#     INCLUDE_ZEROS      : TRUE  -> map genes with zero transcription values
#                          FALSE -> do not map genes with zero transcription
#                                   values
#     TRANSCRIPTION_MIN  : minimum value on the gene transcription scale
#     TRANSCRIPTION_MAX  : maximum value on the gene transcription scale
#     BINDING_MAX        : maximum value on the gene binding scale
#                              if BINDING_MAX is set to NONE, the maximum value
#                              on the gene binding scale is set to the maximum
#                              gene binding value in the data
#     TRANSCRIPTION_PATH : filepath where the gene transcription heatmap will be
#                          saved
#     BINDING_PATH       : filepath where the gene binding heatmap will be saved
#===============================================================================

# save the default warning option
default_warn <- getOption("warn")

# suppress warnings when loading packages
options(warn = -1)
library(ggplot2)
library(svglite)
options(warn = default_warn)

# height and width of images in centimeters
image_dimensions <- c(5, 15)

# remove titles, labels, lines, tick marks, padding and whitespace
# use monospaced font in legend text so that both heatmaps are properly aligned
minimal_theme <- theme(plot.margin = unit(c(0, 0, -0.5, -0.5), "line"),
                       title       = element_blank(),
                       axis.text   = element_blank(),
                       axis.ticks  = element_blank(),
                       legend.text = element_text(family = "mono"))

# color scale for transcription heatmap
# add plus sign to legend text so that both heatmaps are properly aligned
# are properly aligned
blue_white_red_scale <- scale_fill_gradient2(labels   = function(x)
                                                        sprintf("%+d", x),
                                             low      = "blue",
                                             mid      = "white",
                                             high     = "red",
                                             midpoint = 0,
                                             guide    = "colorbar")

# color scale for binding heatmap
black_yellow_scale <- scale_fill_gradient(labels = function(x)
                                                     sprintf("%+d", x),
                                          low    = "black",
                                          high   = "yellow",
                                          guide  = "colorbar")

# save a plot with a given scale, theme and dimensions (cm) to a given file
draw_heatmap <- function(ggplot, fill_scale, theme,
                         dimension_vector, filepath) {
    map <- ggplot + geom_raster() +
                    scale_x_continuous(expand = c(0,0)) +
                    scale_y_continuous(expand = c(0,0)) +
                    fill_scale +
                    theme
    ggsave(filepath,
           plot   = map,
           width  = dimension_vector[2],
           height = dimension_vector[1])
}

# append a column of meaningless y values to a data frame
# reference: <https://stackoverflow.com/a/21911221>
expand_grid_df <- function(...) {
    Reduce(function(...) merge(..., by = NULL), list(...))
}

# generate a copy of a data frame in which all values in a given column greater
# than a given max are set to max and all values less than a given min are set
# to min
# the data are sorted by an optional sort column and a given subset of columns
# are extracted to form the output data frame
flatten_outliers <- function(data, test, min, max, sort = NULL,
                             selection = NULL) {
    # copy data into a local variable so that original data is not modified
    modified_data <- data
    # iterate through every row in data frame
    for (row_index in c(1:nrow(modified_data))) {
        # flatten data in test column (set outliers to min or max)
        if (modified_data[row_index, test] < min) {
            modified_data[row_index, test] <- min
        } else if (modified_data[row_index, test] > max) {
            modified_data[row_index, test] <- max
        }
    }
    # sort in ascending order by sort column, if given
    if (!is.null(sort)) {
        modified_data <- modified_data[order(modified_data[[sort]]), ]
    }
    # create a subset using selected columns, if given
    if (!is.null(selection)) {
        modified_data <- subset(modified_data, select = selection)
    }
    # reset row names (1, 2, 3, ... nrows)
    rownames(modified_data) <- NULL
    return(modified_data)
}

# store command line arguments into a list with given names and convert numeric
# strings to doubles
store_arguments <- function(name_vector) {
    # store command line arguments in a list
    argument_list <- as.list(commandArgs(trailingOnly = TRUE))
    # iterate through every argument in argument list
    for (index in c(1:length(argument_list))) {
        # if argument is a numeric string, convert it to double
        if (suppressWarnings(!is.na(as.double(argument_list[index])))) {
            argument_list[index] <- as.double(argument_list[index])
        }
    }
    # name arguments using given name vector
    names(argument_list) <- name_vector
    return(argument_list)
}

# read arguments from command line
argument_names <- c("csv_path", "include_zeros", "transcription_min",
                    "transcription_max", "binding_max", "transcription_path",
                    "binding_path")
args <- store_arguments(argument_names)

# read data from CSV
# first column -> transcription data, second column -> binding data
gene_data <- read.csv(args[["csv_path"]], header = FALSE)

# standardize column names
# first column -> "transcription", second column -> "binding"
colnames(gene_data) <- c("transcription", "binding")

# remove genes with zero transcription values, if requested
if (args[["include_zeros"]] == "FALSE") {
    gene_data <- gene_data[which(gene_data[["transcription"]] != 0), ]
}

# filter transcription data from gene data
# remove transcription outliers
transcription_data <- flatten_outliers(gene_data, "transcription",
                                       args[["transcription_min"]],
                                       args[["transcription_max"]],
                                       "transcription", c("transcription"))
transcription_data$x_data <- attr(transcription_data, "row.names") - 1
# append meaningless y values (-1, 0 and 1) to every x value
transcription_data <- expand_grid_df(transcription_data,
                                     data.frame(y_data = -1:1))

# filter binding data from gene data
# remove transcription outliers
binding_data <- flatten_outliers(gene_data, "transcription",
                                 args[["transcription_min"]],
                                 args[["transcription_max"]], "transcription",
                                 c("binding"))
# remove binding outliers, if given
if (args[["binding_max"]] != "NONE") {
    binding_data <- flatten_outliers(binding_data, "binding", 0,
                                     args[["binding_max"]])
}
binding_data$x_data <- attr(binding_data, "row.names") - 1
# append meaningless y values (-1, 0 and 1) to every x value
binding_data <- expand_grid_df(binding_data, data.frame(y_data = -1:1))

# map transcription data
transcription_map <- ggplot(transcription_data,
                            aes(x = x_data, y = y_data, fill = transcription))
draw_heatmap(transcription_map, blue_white_red_scale, minimal_theme,
             image_dimensions, filepath = args[["transcription_path"]])

# map binding data
binding_map <- ggplot(binding_data, aes(x = x_data, y = y_data, fill = binding))
draw_heatmap(binding_map, black_yellow_scale, minimal_theme, image_dimensions,
             filepath = args[["binding_path"]])