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
        templateData, $elt, i;

    if (data.lines.length) {
        // File is loaded
        templateData = { filename: filename, rows: [] };
        for (i = 0; i < data.lines.length; i++) {
            templateData.rows.push({ line: i+1, code: data.lines[i][0], unbreakable: !data.lines[i][1]});
        }
        var $elt = $( this.programListingTemplate(templateData) );
        $elt.find('.code').each(this.markupPerlVars.bind(this));
        this.files[filename].resolve($elt);

    } else {
        // Not loaded
        this.files[filename].reject();

        // remove the deferred object so we can ask for it again later
        delete this.files[filename];
    }
};

FileManager.prototype.re = [
    /((\$\w+)(\[)(.*?)(\]))/g,   // array element
    /((\@\w+)(\[)(.*?)(\]))/g,   // array slice
    /((\$\w+)(\{)(.*?)(\}))/g,   // hash elt
    /((\@\w+)(\{)(.*?)(\}))/g,   // hash slice
    /(\$\w+)(?![{[])/g,  // scalar
    /(\@\w+)(?![{[])/g,  // array
    /(\%\w+)/g,          // hash
];
FileManager.prototype.markupPerlVars = function(idx, codeElt) {
    var html = codeElt.innerText,
        newHtml = '',
        replacement,
        i,
        re,
        sigil,
        varname,
        matches,
        prematch,
        madeChange = true;

    while(madeChange) {
        madeChange = false;

        for (i = 0; i < this.re.length; i++) {
            re = this.re[i];
            while (re.test(html)) {
                madeChange = true;
                prematch = html.slice(0, re.lastIndex - RegExp.$1.length);

                if (RegExp.$3) {
                    // array or hash portion
                    if (RegExp.$3 === '[') {
                        sigil = '@';
                    } else if (RegExp.$3 === '{') {
                        sigil = '%';
                    }
                    varname = RegExp.$1.slice(1);
                    replacement = '<span class="popup-perl-var" data-eval="'
                                + sigil + varname + '">' + RegExp.$3 + RegExp.$4
                                + '</span><span class="popup-perl-var" data-eval="'
                                + RegExp.$1 + '">' + RegExp.$4 + RegExp.$5 + '</span>'
                } else {
                    // whole hash, array or scalar
                    replacement = '<span class="popup-perl-var" data-eval="'
                                + RegExp.$1 + '">' + RegExp.$1 + '</span>';
                }
                newHtml = newHtml
                            + prematch
                            + replacement;
                html = html.slice(prematch.length + RegExp.$1.length)
                re.lastIndex += replacement.length - RegExp.$1.length;
            }
        }
    }
    for (i = 0; i < this.re.length; i++) {
        this.re[i].lastIndex = 0;
    }
    $(codeElt).html(newHtml + html);
};

