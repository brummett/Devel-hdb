( function($) {

    var treeTemplate;

    $.fn.filePicker = function( options ) {
        treeTemplate = treeTemplate || Handlebars.compile($('#sub-picker-tree').html());

        var settings = $.extend({
            picked: function(pkg, name) { },
            treeTemplate: treeTemplate
        }, options);

        function expandListForPackage($list, pkg) {
            options.restInterface.packageInfo(pkg)
                    .done(handleData);

            function handleData(data) {
                var templateData = {
                        subs: data.subroutines.map(function(v) { return v.name }),
                        packages: data.packages.map(function(v) { return v.name }),
                        package_name: pkg === 'main' ? '' : pkg
                    };
                $list.siblings('input[type="checkbox"]').removeAttr('unfilled');
                $list.html( settings.treeTemplate(templateData) );
            }
        }


        this.each(function() {
            var $this = $(this),
                $tree_list = $this.find('ul');

            $this.on('click', '.subroutine', function(e) {
                e.preventDefault();
                var $elt = $(e.currentTarget);
                settings.picked( $elt.attr('data-package'), $elt.attr('data-sub'));
            });
            $this.on('change', 'input[type="checkbox"][unfilled]', function(e) {
                var $elt = $(e.currentTarget),
                    $list = $elt.siblings('ul');
                expandListForPackage($list, $elt.attr('id'));
            });
            expandListForPackage($tree_list, 'main')
        });
        return this;
    };


})(jQuery);
