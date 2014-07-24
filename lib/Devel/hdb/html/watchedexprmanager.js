function WatchedExprManager(rest_api) {
    var $watchExpressions = $('#watch-expressions-container'),
        watchedExpressionTemplate = Handlebars.compile( $('#watched-expr-template').html() );

    function isAlreadyWatching(expr) {
        return $watchExpressions.find('.watched-expression[data-expr="'+expr+'"]').length != 0;
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
            var perlValue = PerlValue.parseFromEval(data);
            renderPerlValueIntoElement(expr, perlValue, $elt);
        };
    }

    function makeEvalResultFailHandler(expr, $elt) {
        return function(jqxhr, text_status, error_thrown) {
            if (jqxhr.status == 409) {
                // exception
                debugger;
                var exception = PerlValue.exception();
                renderResult(exception);
                1;
            }
        };
    }

    this.updateExpressions = function() {
        $watchExpressions.find('.watched-expression').each(function() {
            var $elt = $(this),
                expr = $elt.attr('data-expr');

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
            originalExpr = $container.find('.watched-expression').attr('data-expr'),
            $watchedExprDiv = $container.find('.watched-expression');
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
            $target.closest('.watched-expression-form').hide();
            $watchedExprDiv.attr('data-expr', expr);

            $watchedExprDiv.find('.expr').text(expr)
            rest_api.eval(expr, 1)
                    .done( makeEvalResultDoneHandler(expr, $watchedExprDiv))
                    .fail( makeEvalResultFailHandler(expr, $watchedExprDiv))
                    .always(function() { $watchedExprDiv.show(); });
        }

        $addExprButton.prop('disabled', false);
    }

    function addEditWatchExpression(e) {
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
            var $container = $(watchedExpressionTemplate({}));
            $container.find('.watched-expression').hide();
            $container.appendTo($watchExpressions);
            $form = $container.find('.watched-expression-form');
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
            expr = $target.closest('.watched-expression').attr('data-expr');

        if (isEditing($target)) {
            $addExprButton.prop('disabled', false);
        }
        $elt.remove();
    }

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

    $('#add-watch-expr').on('click', addEditWatchExpression);
    $('#watch-expressions')
        .on('click', '.remove-watched-expression', removeWatchedExpression)
        .on('click', '.expr-collapse-button', toggleCollapseWatchExpression)
        .on('dblclick', '.expr', addEditWatchExpression)
        .on('submit', 'form', submitAddedWatchExpression);
}
