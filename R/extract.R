#' Extract and combine estimates and goodness-of-fit statistics from several
#' statistical models.
#'
#' @inheritParams gtsummary
#'
#' @export
extract <- function(models,
                    statistic = 'std.error',
                    statistic_override = NULL,
                    conf_level = 0.95,
                    coef_map = NULL,
                    coef_omit = NULL,
                    gof_map = gtsummary::gof_map,
                    gof_omit = NULL,
                    add_rows = NULL,
                    stars = FALSE,
                    fmt = '%.3f') {


    # models must be a list of models or a single model 
    # TODO: this is code repetition from gtsummary(), but we need it over there
    # as well for sanity checks. This doesn't matter at all, but maybe there's
    # a more elegant solution.
    if (!'list' %in% class(models)) {
        models <- list(models)
    }

    # model names
    if (is.null(names(models))) {
        model_names <- paste('Model', 1:length(models))
    } else {
        if (any(names(models) == '')) {
            stop('Model names cannot include empty strings. Please make sure that every object in the `models` list has a unique, non-empty name. If the `models` list has no names at all, `gtsummary` will create some automatically.')
        }
        model_names <- names(models)
    }

    # if statistics_override is a single function, repeat it in a list to allow map
    if (is.function(statistic_override)) {
        statistic_override <- rep(list(statistic_override), length(models))
    }

    # extract and combine estimates
    est <- list()
    for (i in seq_along(models)) {
        est[[i]] <- extract_estimates(model = models[[i]],
                                      fmt = fmt,
                                      statistic = statistic,
                                      statistic_override = statistic_override[[i]],
                                      conf_level = conf_level,
                                      stars = stars)

        # coef_map: omit, rename (must be done before join to collapse rows)
        if (!is.null(coef_map)) {
            est[[i]] <- est[[i]][est[[i]]$term %in% names(coef_map),] # omit (white list)
            idx <- match(est[[i]]$term, names(coef_map))
            est[[i]]$term <- coef_map[idx] # rename

            # defensive programming
            if (any(table(est[[i]]$term) > 2)) {
                msg <- paste('You are trying to assign the same name to two different variables in model', i)
                stop(msg)
            }
        }
        # coef_omit
        if (!is.null(coef_omit)) {
            est[[i]] <- est[[i]] %>%
                        dplyr::filter(!stringr::str_detect(term, coef_omit))
        }
    }

    est <- est %>% 
           purrr::reduce(dplyr::full_join, by = c('term', 'statistic'))  %>%
           stats::setNames(c('term', 'statistic', model_names)) %>%
           dplyr::mutate(group = 'estimates') %>%
           dplyr::select(group, term, statistic, names(.))

    # reorder estimates (must be done after join
    if (!is.null(coef_map)) {
        idx <- match(est[['term']], coef_map)
        est <- est[order(idx, est[['statistic']]),]
    }

    # extract and combine gof
    gof <- models %>%
           purrr::map(extract_gof, fmt = fmt, gof_map = gof_map)  %>%
           purrr::reduce(dplyr::full_join, by = 'term') %>%
           stats::setNames(c('term', model_names))

    # add_rows to bottom of gof
    if (!is.null(add_rows)) {
        add_rows <- lapply(add_rows, as.character) %>%  # TODO: remove once sanity checks are complete
                    do.call('rbind', .) %>%
                    data.frame(stringsAsFactors = FALSE) %>%
                    stats::setNames(names(gof))
        gof <- dplyr::bind_rows(gof, add_rows)
    }

    # add gof row identifier
    gof <- gof %>%
           dplyr::mutate(group = 'gof') %>%
           dplyr::select(group, term, names(.))

    # omit gof using regex
    if (!is.null(gof_omit)) {
        gof <- gof %>%
               dplyr::filter(!stringr::str_detect(term, gof_omit))
    }


    # gof_map: omit, reorder, rename
    gof <- gof[!gof$term %in% gof_map$raw[gof_map$omit],] # omit (black list)
	gof_names <- gof_map$clean[match(gof$term, gof_map$raw)] # rename
	gof_names[is.na(gof_names)] <- gof$term[is.na(gof_names)]
    gof$term <- gof_names
	idx <- match(gof$term, gof_map$clean) # reorder
    gof <- gof[order(idx, gof$term),] 

    # output
    out <- dplyr::bind_rows(est, gof)
    out[is.na(out)] <- ''
    return(out)
}
