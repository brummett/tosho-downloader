use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri :encode-percents;
use Cro::HTTP::Cookie;
use DOM::Tiny;

# download.gg has a 3-step process to download the file.
# Doing a get() on the main URL immediately does a redirect to a landing page.
# The response includes a session cookie.  Resubmit to the same URL including
# the session, and you get a new page that includes a form whose action is the
# download URL.  The form also includes some hidden params.  post() to that
# form and the download starts.

unit class Task::DownloadggDownloader does FileDownloader is Task;

has Cro::HTTP::Cookie @!session-cookies;
has %!dl-form-params;

# Note that the response here is actually from the redirect URL
method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    @!session-cookies = $response.cookies;

    #say "Response cookies:";
    #for @!session-cookies -> $c { say "  {$c.name} => {$c.value} " }

    say "Resending to $!url with session cookies";
    my $re-response = await $.client.get($!url, cookies => @!session-cookies);
    my $dom = DOM::Tiny.parse(await $re-response.body);
    my $form = $dom.at('form');
    die "Didn't find expected form" unless $form;

    %!dl-form-params = self.extract-inputs-from-form($form);

    # The form's action includes the filename, which can have spaces and
    # other things that need to be urlencoded.  For example:
    # https://download.gg/download/123456/[Foo] Some Cool File.ext
    my $dl-url = $form.attr('action');
    if $dl-url ~~ /^ ( .*? 'download/' (\d+) '/' ) (.*) $ / {
        return Cro::Uri.parse("$/[0]" ~ encode-percents("$/[1]"));
    } else {
        die "Can't find download form/action";
    }
}
    
method do-download-request(Cro::Uri $uri --> Promise) {
    return $.client.post($uri,
                         content-type => 'application/x-www-form-urlencoded',
                         headers => [ referer => "$!url" ],
                         cookies => @!session-cookies,
                         body => %!dl-form-params,
                    );
}
