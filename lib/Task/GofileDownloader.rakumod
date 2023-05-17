use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri;

# GoFile has an API we can download through.  You first have to create a
# temp account, which returns a token that must be used for other interaction.
# The URL we get from Tosho has a file-id as the last part of the path.
# This fileId+token gets turned into a download URL and downloaded in
# the usual way

# Based on https://github.com/ltsdw/gofile-downloader

unit class Task::GofileDownloader does FileDownloader is Task;

my Str $dl-token;

# websiteToken is used in the getContent API endpoint.  This is a copy of the
# value used in the web frontend, in the file alljs.js
my Str $website-token = 'fghij';

# The url we're created with looks like https://gofile.io/d/fileId which would
# generate a javascript-driven page if you pointed a browser at it.
# Instead, we'll use that "fileId" and use GoFile's API
submethod TWEAK {
    $dl-token = self!get-dl-token();
    my $file-id = (Cro::Uri.parse($!url).path-segments)[*-1];
    $!url = "https://api.gofile.io/getContent?contentId=$file-id&token=$dl-token&websiteToken=$website-token";
    say "    via API at $!url";
}
    
method !get-dl-token {
    unless $dl-token {
        my $response = await $.client.get('https://api.gofile.io/createAccount');
        my $json-data = await $response.body();
        # looks like: {data => {token => 0eoxBkYGFYmHZ43mxkJpY2vWLeCYW5SV}, status => ok}

        # The original hit https://api.gofile.io/getAccountDetails?token=$api-token
        # to check the status of the account before proceeding. Its response is:
        # {data => {credit => 0, currency => USD, currencySign => $, email => guest1675367646@gofile.io,
        #           filesCount => 0, rootFolder => 96ed5b07-dd08-44e4-bd5d-f73745ee25fb, tier => guest,
        #           token => 0eoxBkYGFYmHZ43mxkJpY2vWLeCYW5SV, total30DDLTraffic => 0, totalSize => 0},
        #   status => ok}

        $dl-token = $json-data<data><token>;
    }
    return $dl-token;
}

method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    my $json = await $response.body();

    # Response looks like:
    # { data => {
    #       childs => [2c5d5a3c-8d58-4256-a774-13a72691959a],
    #       code => fQKBdZ,
    #       contents => {
    #           2c5d5a3c-8d58-4256-a774-13a72691959a => {
    #               createTime => 1680113395,
    #               directLink => https://store11.gofile.io/download/direct/same-uuid/url-encoded-filename.ext,
    #               downloadCount => 82,
    #               id => 2c5d5a3c-8d58-4256-a774-13a72691959a,
    #               link => https://file40.gofile.io/download/same-uuid/url-encoded-filename.ext,
    #               md5 => fcb830ed5d5d1e68f7fa965899c5299c,
    #               mimetype => video/x-matroska,
    #               name => filename.ext,
    #               parentFolder => 485b8173-1a2e-45be-9013-991e17dcded2,
    #               serverChoosen => file40, size => 298394797, type => file
    #           }
    #       },
    #       createTime => 1680113395,
    #       id => 485b8173-1a2e-45be-9013-991e17dcded2,
    #       name => fQKBdZ,
    #       parentFolder => 9ddbbd18-e5c0-4809-8515-3877e205f55a,
    #       public => True,
    #       totalDownloadCount => 82,
    #       totalSize => 298394797,
    #       type => folder
    #   },
    #   status => ok}
    # The response indicates multiple files can be in each "folder", but Tosho only ever does one
    if $json<data><contents>.elems != 1 {
        die "Expected 1 'contents' item, but got { $json<data><contents>.elems }";
    }
    my $dl-link;
    for $json<data><contents>.values -> $content {
        $dl-link = $content<link>;
    }

    @!dl-headers =
        Cookie => "accountToken=$dl-token",
        'Accept-Encoding' => "gzip, deflate, br",
        #'User-Agent' => $user-agent,
        'Accept' => '*/*',
        'Referer' => $dl-link ~ ($dl-link.substr(*-1) ne '/' ?? '/' !! ''),
        'Origin' => $dl-link,
        'Connection' => 'keep-alive',
        'Sec-Fetch-Dest' => 'empty',
        'Sec-Fetch-Mode' => 'cors',
        'Sec-Fetch-Site' => 'same-site',
        'Pragma' => 'no-cache',
        'Cache-Control' => 'no-cache';
    
    say "    file DL is at $dl-link";
    return Cro::Uri.parse($dl-link);
}
