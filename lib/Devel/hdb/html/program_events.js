// A class to represent things that get stored in the 'events' list
// after hitting a control button.  They render a modal window that may
// perform some action
var ProgramEvent;
(function() {
    var templates = undefined;
    function fillTemplates() {
        if (!templates) {
            templates = {
                fork: Handlebars.compile($('#forked-child-modal-template').html() ),
                exit: Handlebars.compile($('#program-terminated-modal-template').html() ),
                exception: Handlebars.compile($('#uncaught-exception-modal-template').html() ),
                trace_diff: Handlebars.compile($('#trace-diff-modal-template').html() )
            };
        }
    }

    ProgramEvent = function(params) {
        fillTemplates();
        if (! (params.type in templates)) {
            throw new Error('Unknown type of event: ' + params.type);
        }

        for (var k in params) {
            this[k] = params[k];
        }

        // an exception's 'value' is special
        if (this.type == 'exception') {
            this.value = PerlValue.parseFromEval(this.value);
        }

        var template = templates[this.type];
        this.render = function($container) {
            var $modal = $(template(this));

            $modal.appendTo($container)
                  .modal({ backdrop: true, keyboard: true, show: true })
                  .focus()
                  .on('hidden', function(e) {
                        $modal.remove();
                    });

            var d = $.Deferred();
            $modal.on('click', '.btn', function(e) {
                var $target = $(e.currentTarget);
                if ($target.hasClass('continue-child')) {
                    e.preventDefault();
                    $.ajax({
                        type: 'POST',
                        url: $target.attr('href'),
                    }).fail(function(jqxhr, text_status, error_thrown) {
                        console.error('Problem sending continue.  text_status: '+text_status);
                        concole.error('  error_thrown'+error_thrown);
                        alert('Problem sending continue: '+text_status);
                    });
                }
                d.resolve($target.val());
                $modal.modal('hide');
            });

            return d.promise();
        };

        return this;
    };
})();

