// Represents a Perl value
function PerlValue(value) {
    this.value = value;
}
// We'd rather use a template for this, but Handlebars templates can't
// do different things depending on the type
// FIXME: maybe use a Handlebars helper and differnet templates for array, object, etc
PerlValue.prototype.render = function() {
    return $( renderPart(this.value) );

    function renderPart(value) {
        var html = '',
            valueType = typeof value,
            k;
        if ((value === undefined) || (value === null)) {
            html += '<span class="label"><i>undef</i></span>';

        } else if ($.isArray(value)) {
            html += '<span class="collapsable">ARRAY ('+value.length+')</span><dl>';
            for (k = 0; k < value.length; k++) {
                html += '<dt>'+ k +'</dy><dd>' + renderPart(value[k]) + '</dd>';
            }
            html += '</dl>';

        } else if (valueType == 'object') {
            html += '<span class="collapsable">HASH ('+ Object.keys(value).length + ')</span><dl>';
            for (k in value) {
                html += '<dt>'+k+'</dt><dd>'+ renderPart(value[k]) + '</dd>';
            }
            html += '</dl>';
        } else {
            html += '<span>' + value + '</span>';
        }
        return html;
    }
};
