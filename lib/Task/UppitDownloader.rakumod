use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri :encode-percents;
use DOM::Tiny;

# Uppit has a 2-step process to get the download link.
# First is a "landing page" with a button labeled "Start Download".
# Submitting that form leads to a page with a link styled as a button
# labeled "Download".
#
# Both requests are made to the same URI.  The first is a get(), and the
# second is a post().  The form parameters and final download link are very
# similar to those used by ClickNUpload

unit class Task::UppitDownloader does FileDownloader is Task;

has Str $!fname;

method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    my $original-uri = $response.request.uri;

    my %page1-inputs = self!handle-landing-page($response);
    $!fname = %page1-inputs<fname>;  # The file name we'll be downloading.  Appears in the final DL url

    say "POST to $original-uri";
    my $form-response = await $.client.post(
                                $original-uri,
                                content-type => 'application/x-www-form-urlencoded',
                                headers => [ referer => "$original-uri" ],
                                body => %page1-inputs,
                            );

    my $l = self!handle-download-page($form-response);
    return $l;
}
    

method do-download-request(Cro::Uri $uri --> Promise) {
    return $.client.get($uri,
                        user_agent => $!user-agent,
                    );
}

method !handle-landing-page(Cro::HTTP::Response $response --> Associative) {
    my $dom = DOM::Tiny.parse(await $response.body);
    my %inputs = self!extract-inputs-from-form($dom.at('form[name=pre]'));
    return %inputs;
}

method !handle-download-page(Cro::HTTP::Response $response --> Cro::Uri) {
    my $dom = DOM::Tiny.parse(await $response.body);
    my $dl-link = $dom.at('a.btn.btn-primary');
    die "Didn't find DL link at { $response.request.uri }" unless $dl-link;
    
    say "Response body: ",await($response.body) unless $dl-link;

    # The ultimate DL link contains spaces.  We need to urlencode just that
    # part of the URL otherwise DOM::Tiny.parse() complains.  Luckily, we
    # received the filename as an input in the original get()
    say "got dl-link { $dl-link.attr('href') }";
    my $fname = $!fname;
    my $encoded-fname = encode-percents($fname);
    (my $dl-url = $dl-link.attr('href') ) ~~ s/ "/$fname" $ /\/$encoded-fname/;
    say "  encoded as $dl-url";

    return Cro::Uri.parse($dl-url);
}

method !extract-inputs-from-form(DOM::Tiny $form --> Associative) {
    my %inputs = $form.find('input')
                      .map(-> $input { $input.attr('name') => $input.attr('value') });
    return %inputs;
}
