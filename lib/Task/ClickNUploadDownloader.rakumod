use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri :encode-percents;
use DOM::Tiny;

# ClickNUpload has a 3-step process to get the download link.
# First, a "landing page" where there's a form button labeled "Slow Download"
# Submitting that form with a post() presents another form with a 4-digit
# captcha, sometimes also with a countdown timer.  Submitting that form
# with a post() presents the final page that includes the download link.
#
# All these requests are made to the same uri.  The first is a get(), the
# other two are post().  The difference in the two post() requests is the
# form params.

unit class Task::ClickNUploadDownloader does FileDownloader is Task;

has Str $!fname;

# After resolving the DL link, doing a get() on it dies with:
#    X::IO::Socket::Async::SSL::Verification+{X::Await::Died}+{X::Promise::Broken} exception:
#    Server certificate verification failed: unable to get local issuer certificate
# wget also complains:
#    ERROR: cannot verify mover04.clicknupload.net's certificate, issued by ‘CN=R3,O=Let's Encrypt,C=US’:
#   Unable to locally verify the issuer's authority.
# The workaround is to do the get with: ca => { :insecure }
submethod TWEAK() { $!dl-ca-insecure = True }

method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    my $original-uri = $response.request.uri;

    my %page1-inputs = self!handle-landing-page($response);
    $!fname = %page1-inputs<fname>;  # The file name we'll be downloading.  Appears in the final DL url

    say "POST to $original-uri";
    my $form1-response = await $.client.post(
                                $original-uri,
                                content-type => 'application/x-www-form-urlencoded',
                                headers => [ referer => "$original-uri" ],
                                body => %page1-inputs,
                            );

    my %page2-inputs = self!handle-captcha-page($form1-response);
    say "solved captcha: %page2-inputs<code>";
    say "POST again to $original-uri";
    my $form2-response = await $.client.post(
                                $original-uri,
                                content-type => 'application/x-www-form-urlencoded',
                                headers => [ referer => "$original-uri" ],
                                body => %page2-inputs,
                            );

    my $l = self!handle-download-page($form2-response);
    die "Couldn't find download link via $original-uri" unless $l;
    return $l;
}

method !handle-landing-page(Cro::HTTP::Response $response --> Associative) {
    my $dom = DOM::Tiny.parse(await $response.body);
    my %inputs = self!extract-inputs-from-form($dom.at('.download form'));
    return %inputs;
}

method !handle-captcha-page(Cro::HTTP::Response $response --> Associative) {
    my $dom = DOM::Tiny.parse(await $response.body);

    self!handle-countdown($dom);

    my $form = $dom.at('form[name=F1]');
    my $captcha = self!solve-captcha($form);

    my %inputs = self!extract-inputs-from-form($form);
    %inputs<code> = $captcha;
    %inputs<adblock_detected> = '0';
    return %inputs;
}

method !handle-download-page(Cro::HTTP::Response $response --> Cro::Uri) {
    my $dom = DOM::Tiny.parse(await $response.body);
    my $dl-link = $dom.at('a.downloadbtn');
    unless $dl-link {
        say "Didn't find DL link at { $response.request.uri }";
        return;
    }

    # The ultimate DL link contains spaces.  We need to urlencode just that
    # part of the URL.  Luckily, we received the filename as an input in the
    # original get()
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

method !handle-countdown(DOM::Tiny $dom) {
    if my $countdown = $dom.at('span#countdown span.seconds') {
        my $seconds = $countdown.text.Int;
        say "  Pausing for $seconds countdown...";
        await Promise.in($seconds+1);
    }
}

# The captcha is presented as 4 span elements that display numbers.
# The HTML has them out of order, but uses "padding-left" styles to display
# them in the proper order.  Find the elements, sort them in the right order,
# and return the 4-digit string.
method !solve-captcha(DOM::Tiny $form) {
    my $solution = $form.find('div.download span[style*=padding-left]')
                        .sort(&_captcha-element-ordering)
                        .map(*.text)
                        .join('');
    return $solution;
}
sub _captcha-element-ordering(DOM::Tiny $element) {
    my $style = $element.attr('style');
    $style ~~ m/'padding-left:' (\d+) 'px'/;
    return $/[0].Int;
}
