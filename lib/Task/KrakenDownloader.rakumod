use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri;
use DOM::Tiny;

unit class Task::KrakenDownloader does FileDownloader is Task;

constant $wk-boundary = '------WebKitFormBoundary7MA4YWxkTrZu0gW';

method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    my $original-uri = $response.request.uri;

    my $dom = DOM::Tiny.parse(await $response.body);

    # There's a form with a download button inside.  Submit the form and get
    # back a bit of JSON with a URL of the file

    my $form = $dom.at('#dl-form');
    my Str $dl-token = $form.at('#dl-token').attr('value');  # hidden input
    my Str $file-hash = $dom.at('div[data-file-hash]').attr('data-file-hash');

    my $form-action = $original-uri.add( $form.attr('action') );

    say "    submitting form to $form-action";
    my $dl = await $.client.post($form-action,
                content-type => "multipart/form-data; boundary=$wk-boundary",
                headers => [
                    hash => $file-hash,
                ],
                body => [
                    token => $dl-token,
                ],
            );

    my $dl-info = await $dl.body;
    if $dl-info<status> ne 'ok' {
        die "Bad response status processing $.filename: ",$dl-info.raku;
    }
    say "    direct download $.filename: ",$dl-info<url>;

    return Cro::Uri.parse($dl-info<url>);
}
