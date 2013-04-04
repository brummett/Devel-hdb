function FileManager(messageHandler) {
    this.files = {};
    this.messageHandler = messageHandler;
    this.programListingTemplate = Handlebars.compile( $('#program-listing-template').html() );

    messageHandler.addHandler('sourcefile', this.sourceFileLoaded.bind(this));
}

FileManager.prototype.loadFile = function(filename) {
    if (! (filename in this.files)) {
        var d = $.Deferred();
        $.ajax({url: 'sourcefile',
                type: 'GET',
                data: { f: filename },
                success: this.messageHandler.consumer,
                // TODO replace with something better
                error: function() { alert('Cannot load file '+filename); }
            });

        this.files[filename] = d;
    }
    return this.files[filename].promise()
};

FileManager.prototype.sourceFileLoaded = function(data) {
    var filename = data.filename,
        fm = this,
        templateData, $elt, i;

    if (data.lines.length) {
        // File is loaded
        templateData = { filename: filename, rows: [] };
        for (i = 0; i < data.lines.length; i++) {
            templateData.rows.push({ line: i+1, code: data.lines[i][0], unbreakable: !data.lines[i][1]});
        }
        var $elt = $( this.programListingTemplate(templateData) );
        $elt.find('.code').each(function(idx,codeElt) {
            codeElt = $(codeElt);
            codeElt.html( fm.markupPerlVars(codeElt.text()));
        });
        this.files[filename].resolve($elt);

    } else {
        // Not loaded
        this.files[filename].reject();

        // remove the deferred object so we can ask for it again later
        delete this.files[filename];
    }
};

FileManager.prototype.markupPerlVars = function(line) {
    var i = 0,  // index into the string
        output = '';   // the string we're returning

    while (i < line.length) {
        var remaining = line.substr(i);
        if (/^(([$@])(\w+(::\w+)*)([[{]))/.test(remaining)) {
            // Array or hash element or slice
            var varPrefix = RegExp.$1;
            var sigil = RegExp.$2;
            var isSlice = sigil === '@';
            var varName = RegExp.$3;
            var openParen = RegExp.$5;
            var isArray = openParen === '[';
            var endpos = remaining.indexOf(isArray ? ']' : '}');
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
                        + sigil + varName + '">'
                        + arrayIndex + '</span>';
            i += (endpos + 1);

        } else if (/^(([$@%*])(\w+(::\w+)*))/.test(remaining)) {
            // whole scalar, array, hash or glob
            output += '<span class="popup-perl-var" data-eval="'
                        + RegExp.$1 + '">' + RegExp.$1 + '</span>';
            i += RegExp.$1.length;

        } else if (/^(([$@%])(\^.|.))/.test(remaining)) {
            // A perl special var
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

