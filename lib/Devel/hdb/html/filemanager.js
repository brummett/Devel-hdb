function FileManager(rest_interface) {
    var files = {},
        programListingTemplate = Handlebars.compile( $('#program-listing-template').html() ),
        array_or_hash_element_or_slice = /^(([$@])(\w+(::\w+)*)([[{]))/,
        scalar_array_hash_or_glob = /^(([$@%*])(\w+(::\w+)*))/,
        basic_dereference = /^(([@%*])(\$\w+(::\w+)*))/,
        perl_special_var = /^(([$@%])(?!&(#x[0-9A-Fa-f]{1,4}|quot|amp|apos|lt|gt);)(\^.|.))/,
        other_perl_special_var = /^(\$&(quot|amp|apos|lt|gt|#x27|#x60);)/;

    var markupPerlVars = function(line) {
        var i = 0,  // index into the string
            output = '';   // the string we're returning

        while (i < line.length) {
            var remaining = line.substr(i);
            if (array_or_hash_element_or_slice.test(remaining)) {
                var varPrefix = RegExp.$1,
                    sigil = RegExp.$2,
                    isSlice = sigil === '@',
                    varName = RegExp.$3,
                    openParen = RegExp.$5,
                    isArray = openParen === '[',
                    containerSigil = isArray ? '@' : '%',
                    endpos = remaining.indexOf(isArray ? ']' : '}');
                if (endpos === null) {
                    // Didn't find it - bail out
                    output = varPrefix;
                    i += varPrefix.length;
                    continue;
                }
                // The indexing portion of the variable expression
                // includes the parens around it
                var arrayIndex = remaining.substring(varPrefix.length - 1, endpos + 1);
                output += '<span class="popup-perl-var" data-eval="'
                            + (isArray ? '@' : '%') + varName + '">' + sigil + varName
                            + '</span><span class="popup-perl-var" data-eval="'
                            + remaining.substring(0, endpos + 1) + '" data-part-of="'
                            + containerSigil + varName + '">'
                            + arrayIndex + '</span>';
                i += (endpos + 1);

            } else if (basic_dereference.test(remaining)) {
                output += '<span class="popup-perl-var" data-eval="'
                            + RegExp.$3 + '">' + RegExp.$1 + '</span>';
                i += RegExp.$1.length;

            } else if (scalar_array_hash_or_glob.test(remaining)) {
                output += '<span class="popup-perl-var" data-eval="'
                            + RegExp.$1 + '">' + RegExp.$1 + '</span>';
                i += RegExp.$1.length;

            } else if (perl_special_var.test(remaining)) {
                output += '<span class="popup-perl-var" data-eval="'
                            + RegExp.$1 + '">' + RegExp.$1 + '</span>';
                i += RegExp.$1.length;

            } else if (other_perl_special_var.test(remaining)) {
                output += '<span class="popup-perl-var" data-eval="'
                            + RegExp.$1 + '">' + RegExp.$1 + '</span>';
                i += RegExp.$1.length;

            } else {
                // Found no perl vars
                output += remaining.charAt(0);
                i++;
                continue;
            }
        }
        return output;
    };

    var sourceFileLoaded = function(filename, source_lines) {
        var templateData, $elt, i;

        if (source_lines) {
            // File is loaded
            templateData = { filename: filename, rows: [] };
            for (i = 0; i < source_lines.length; i++) {
                templateData.rows.push({
                        line: i+1,
                        code: Handlebars.Utils.escapeExpression(source_lines[i][0]),  // This gets re-htmlified below in codeElt.html()
                        unbreakable: !source_lines[i][1]
                });
            }
            var $elt = $( programListingTemplate(templateData) );
            $elt.find('.code').each(function(idx,codeElt) {
                codeElt = $(codeElt);
                codeElt.html( markupPerlVars(codeElt.text()));
            });
            files[filename].resolve($elt);

        } else {
            // Not loaded
            files[filename].reject();

            // remove the deferred object so we can ask for it again later
            delete files[filename];
        }
    };

    this.loadFile = function(filename) {
        if (! (filename in files)) {
            var d = files[filename] = $.Deferred();
            rest_interface.fileSourceAndBreakable(filename)
                .done(function(data) { sourceFileLoaded(filename, data); });
        }
        return files[filename].promise()
    };
}
