function WatchedExprManager(rest_api) {
    var $watchExpressions = $('#watch-expressions-container'),
        watchedExpressionTemplate = Handlebars.compile( $('#watched-expr-template').html() ),
        watchedExpressionToDivId = {},
        watchedExprSerial = 0;

    function isAlreadyWatching(expr) {
        return (expr in watchedExpressionToDivId);
    }

    function exprForElt($elt) {
        var divId = $elt.closest('.watched-expression').attr('id');
        for (var expr in watchedExpressionToDivId) {
            if (watchedExpressionToDivId[expr] == divId) {
                return expr;
            }
        }
        return null;
    }

    function setIsEditing($elt, value) {
        if (value) {
            $elt.closest('.expr-container').addClass('editing');
        } else {
            $elt.closest('.expr-container').removeClass('editing');
        }
    }

    function isEditing($elt) {
        return $elt.closest('.expr-container').hasClass('editing');
    }

    function renderPerlValueIntoElement(expr, perlValue, $elt) {
        $elt.find('.value').empty().append(perlValue.render());
    }

    function makeEvalResultDoneHandler(expr, $elt) {
        return function(data) {
            // We're always eval-ing in list context
            // If the array contains 1 item, use that 1 item instead
            if (typeof(data) == 'object'
                && data.__reftype == 'ARRAY'
                && data.__value.length == 1
            ) {
                data = data.__value[0];
            }
            var perlValue = PerlValue.parseFromEval(data);
            renderPerlValueIntoElement(expr, perlValue, $elt);
        };
    }

    function makeEvalResultFailHandler(expr, $elt) {
        return function(jqxhr, text_status, error_thrown) {
            if (jqxhr.status == 409) {
                // exception
                var ex = new PerlValue.exception(jqxhr.responseJSON);
                renderPerlValueIntoElement(expr, ex, $elt);
                1;
            }
        };
    }

    this.updateExpressions = function() {
        $.each(watchedExpressionToDivId, function(expr, divId) {
            var $elt = $('#' + divId);

            rest_api.eval(expr, 1)
                    .done( makeEvalResultDoneHandler(expr, $elt))
                    .fail( makeEvalResultFailHandler(expr, $elt));
        });
    };

    var $addExprButton = $('#add-watch-expr');
    function submitAddedWatchExpression(e) {
        var $target = $(e.target),
            expr = $target.find('input').val(),
            $container = $target.closest('.expr-container'),
            $watchedExprDiv = $container.find('.watched-expression'),
            originalExpr = exprForElt($watchedExprDiv);

        expr = expr.replace(/^\s+|\s+$/g,''); // Remove leading and trailing spaces

        e.preventDefault();

        setIsEditing($target, false);

        if ((expr.length) && (expr == originalExpr)) {
            // They didn't change it
            $container.find('.watched-expression-form').hide();

        } else if (isAlreadyWatching(expr)) {
            // new, but it duplicates something already there
            $container.remove();
            alert('Already watching '+expr);

        } else {
            retrieveCurrentValueForWatchedExpressionForm($target);
        }

        $addExprButton.prop('disabled', false);
    }

    function retrieveCurrentValueForWatchedExpressionForm($form) {
        var expr = $form.find('input').val(),
            $container = $form.closest('.expr-container'),
            $watchedExprDiv = $container.find('.watched-expression');

        watchedExpressionToDivId[expr] = $watchedExprDiv.attr('id');
        $form.closest('.watched-expression-form').hide();

        $watchedExprDiv.find('.expr').text(expr)
        rest_api.eval(expr, 1)
                .done( makeEvalResultDoneHandler(expr, $watchedExprDiv))
                .fail( makeEvalResultFailHandler(expr, $watchedExprDiv))
                .always(function() { $watchedExprDiv.show(); });
    }

    function appendNewWatchExpressionToPane(expr, isWatchpoint) {
        var divId = 'watch' + (++watchedExprSerial),
            $container = $(watchedExpressionTemplate({id: divId, expr: expr, isWatchpoint: isWatchpoint})),
            form;

        $container.find('.watched-expression').hide();
        $container.appendTo($watchExpressions);
        $form = $container.find('.watched-expression-form');
        return $form;
    }

    function addOrEditWatchExpression(e) {
        var $target = $(e.target),
            $form, revert;

        e.preventDefault();

        $addExprButton.prop('disabled', true); // disable the add button

        if ($target.hasClass('expr')) {
            // editing an existing expression
            $form = $target.closest('.expr-container').find('.watched-expression-form').show();
            var originalExpr = $target.closest('.watched-expression').attr('data-expr');
            revert = function() {
                $form.hide()
                     .find('input[type="text"]').val(originalExpr);
                setIsEditing($form, false);
            };
                
        } else {
            // Adding a new expression
            $form = appendNewWatchExpressionToPane();
            revert = function() {
                $container.remove();
                setIsEditing($form, false);
            };
        }

        setIsEditing($form, true);

        $form.find('input[type="text"]').keyup(function(e) {
            // If the user presses escape, abort the form
            if (e.keyCode == 27) {
                e.preventDefault();
                $addExprButton.prop('disabled', false);  // re-enable the add button
                revert();
            }
        })
        .trigger('focus');
    }

    function removeWatchedExpression(e) {
        var $target = $(e.target),
            $elt = $target.closest('.expr-container'),
            divId = $target.closest('.watched-expression').attr('id');

        if (isEditing($target)) {
            $addExprButton.prop('disabled', false);
        }
        $elt.remove();

        for (var expr in watchedExpressionToDivId) {
            if (watchedExpressionToDivId[expr] == divId) {
                delete watchedExpressionToDivId[expr];
                break;
            }
        }
    }

    function toggleWatchpoint(e) {
        var $target=$(e.target),
            $elt = $target.closest('.expr-container'),
            divId = $target.closest('.watched-expression').attr('id'),
            expr = exprForElt($target);

        // change/click callback trigger *after* the checkbox element changes state

        e.stopPropagation();
        e.preventDefault();
        var current_state = $target.is(':checked'),
            toggle_fcn = (current_state ? rest_api.createWatchpoint : rest_api.deleteWatchpoint).bind(rest_api);

        toggle_fcn(expr)
            .done(function(result) {
                    1;
            })
            .fail(function(jqxhr, text_status, error_thrown) {
                // didn't work, change the checkbox back to whatever it was before
                $target.attr('checked', ! current_state);
                alert("Error setting watchpoint: " + text_status);
                1;
            });
    }

    this.loadWatchpoints = function() {
        rest_api.getWatchpoints()
                .done(function(wp_list) {
                    wp_list.forEach(function(wp) {
                        var $form = appendNewWatchExpressionToPane(wp.expr, true);
                        retrieveCurrentValueForWatchedExpressionForm($form);
                    });
                })
                .fail(function(jqxhr, text_status, error_thrown) {
                    alert('Error loading watchpoints: ' + text_status);
                });
    };

    this.flash = function(expr) {
        var divId = watchedExpressionToDivId[expr],
            $element = $("#" + divId + ' .expr'),
            count = 10;  // even number so it returns to normal when done

        function toggler() {
            $element.toggleClass('flashed');
            if (--count) {
                setTimeout(toggler, 500);
            }
        }

        toggler();
    };

    function toggleCollapseWatchExpression(e) {
        var $target = $(e.target),
            $toToggle = $target.siblings('dl,ul'),
            is_collapsed = $toToggle.css('display') == 'none';

        e.preventDefault();
        $toToggle.toggle(100, function() {
            if (is_collapsed) {
                $target.removeClass('collapsed');
            } else {
                $target.addClass('collapsed');
            }
        });
    }

    $('#add-watch-expr').on('click', addOrEditWatchExpression);
    $('#watch-expressions')
        .on('click', '.remove-watched-expression', removeWatchedExpression)
        .on('click', '.expr-collapse-button', toggleCollapseWatchExpression)
        .on('dblclick', '.expr', addOrEditWatchExpression)
        .on('submit', 'form', submitAddedWatchExpression)
        .on('change', '.expr-container:not(.editing) input:checkbox.enable-watchpoint', toggleWatchpoint);
}
