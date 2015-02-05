use strict;
use warnings;
use utf8;
use File::Basename 'dirname';
use File::Spec::Functions qw{catdir splitdir rel2abs canonpath};
use lib catdir(dirname(__FILE__), '../lib');
use lib catdir(dirname(__FILE__), 'lib');
use Test::More;
use Mojo::DOM;
use WWW::Crawler::Mojo;
use WWW::Crawler::Mojo::Job;
use Mojo::Message::Response;
use Test::More tests => 33;

sub _weave_form_data {
    WWW::Crawler::Mojo->new->element_handlers->{form}->(@_);
}

{
    my $dom = Mojo::DOM->new(<<EOF);
<div>
    <form action="/index1.html" method="get">
        <input type="text" name="foo" value="default">
        <input type="submit" value="submit">
    </form>
</div>
EOF
    my $ret = _weave_form_data($dom->at('form'));
    is $ret->[0], '/index1.html';
    is $ret->[1], 'GET';
    is $ret->[2], 'foo=default';
}

{
    my $dom = Mojo::DOM->new(<<EOF);
<div>
    <form action="/index1.html" method="post">
        <input type="text" name="foo" value="default">
        <input type="submit" name="bar" value="submit">
    </form>
</div>
EOF
    my $ret = _weave_form_data($dom->at('form'));
    is $ret->[0], '/index1.html';
    is $ret->[1], 'POST';
    is_deeply $ret->[2]->to_hash, {bar => 'submit', foo => 'default'};
}

{
    my $dom = Mojo::DOM->new(<<'EOF');
<html>
    <body>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Some hidden fields and multiple buttons.
                </legend>
                <input type="text" name="foo" value="fooValue">
                <input type="text" name="bar" value="barValue">
                <input type="hidden" name="baz" value="bazValue">
                <input type="hidden" name="yada" value="yadaValue" disabled="disabled">
                <input type="submit" name='btn' value="send">
                <input type="submit" name='btn' value="send2">
                <input type="submit" name='btn3' value="send3">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Simple form.
                </legend>
                <input type="text" name="foo" value="fooValue">
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Checked radio not exists
                </legend>
                <input type="radio" name="foo" value="fooValue2"> fooValue2
                <input type="radio" name="foo" value="fooValue3"> fooValue3
                <input type="submit" value="send">
            </field>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Checked radio exists
                </legend>
                <input type="radio" name="foo" value="fooValue2"> fooValue2
                <input type="radio" name="foo" value="fooValue3" checked="checked"> fooValue3
                <input type="submit" value="send">
            </field>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Radio button with same named hidden for setting default value.
                </legend>
                <input type="hidden" name="foo" value="">
                <input type="radio" name="foo" value="fooValue1"> fooValue1
                <input type="radio" name="foo" value="fooValue2" checked="checked"> fooValue2
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Default checked radio set.
                </legend>
                <input type="radio" name="foo" value="fooValue1"> fooValue1
                <input type="radio" name="foo" value="fooValue2" checked> fooValue2
                <input type="radio" name="foo" value="fooValue3"> fooValue3
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    select.
                </legend>
                <select name="foo">
                    <option value="">a</option>
                    <option value="fooValue1">a</option>
                    <option value="fooValue2">b</option>
                    <option value="a&quot;b">b</option>
                    <option value="a/b">b</option>
                </select>
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Pattern html5 attribute.
                </legend>
                <input type="text" name="foo" value="" pattern="\d\d\d">
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Set type to number.
                </legend>
                <input type="number" name="foo" value="" min="5" max="10">
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor3" method="post">
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    File.
                </legend>
                <input type="text" name="foo" value="">
                <input type="file" name="bar">
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Select with same named hidden field.
                </legend>
                <input type="hidden" name="foo" value="value1">
                <select name="foo">
                    <option value="value2" selected>a</option>
                    <option value="value3" selected>a</option>
                    <option value="value4">a</option>
                </select>
                <input type="submit" value="send">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Special chars.
                </legend>
                <input type="hidden" name="foo" value="やったー">
            </fieldset>
        </form>
        <form action="/receptor1" method="post">
            <fieldset>
                <legend>
                    Textareas.
                </legend>
                <textarea name="foo">foo default</textarea>
                <textarea name="bar" disabled>bar default</textarea>
                <textarea name="baz" required>baz default</textarea>
                <input type="submit" value="send">
            </fieldset>
        </form>
    </body>
</html>
EOF
    {
        my $ret = _weave_form_data($dom->find('form')->[0]);
        is_deeply $ret->[2]->to_hash, {
            baz => 'bazValue', bar => 'barValue', btn => 'send',
            foo => 'fooValue', yada => 'yadaValue'
        };
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[1]);
        is_deeply $ret->[2]->to_hash, {foo => 'fooValue'};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[2]);
        is_deeply $ret->[2]->to_hash, {};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[3]);
        is_deeply $ret->[2]->to_hash, {foo => 'fooValue3'};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[4]);
        is_deeply $ret->[2]->to_hash, {foo => ['', 'fooValue2']};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[5]);
        is_deeply $ret->[2]->to_hash, {foo => 'fooValue2'};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[6]);
        is_deeply $ret->[2]->to_hash, {};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[7]);
        is_deeply $ret->[2]->to_hash, {foo => ''};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[8]);
        is_deeply $ret->[2]->to_hash, {foo => ''};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[9]);
        is_deeply $ret->[2]->to_hash, {};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[10]);
        is_deeply $ret->[2]->to_hash, {foo => ''};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[11]);
        is_deeply $ret->[2]->to_hash, {foo => ['value1', 'value2', 'value3']};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[12]);
        is_deeply $ret->[2]->to_hash, {foo => 'やったー'};
    }
    {
        my $ret = _weave_form_data($dom->find('form')->[13]);
        is_deeply $ret->[2]->to_hash, {foo => 'foo default', bar => 'bar default', baz => 'baz default'};
    }
}

{
    my $html = <<EOF;
<html>
<body>
<form action="/index1.html">
    <input type="text" name="foo" value="default">
    <input type="submit" value="submit">
</form>
<form action="/index2.html" method="post">
    <textarea name="foo">foo</textarea>
    <input type="submit" value="submit">
</form>
<form action="/index2.html" method="post">
    <textarea name="bar">bar</textarea>
    <input type="submit" value="submit">
</form>
</body>
</html>
EOF
    
    my $res = Mojo::Message::Response->new;
    $res->code(200);
    $res->body($html);
    $res->headers->content_type('text/html');
    
    my $bot = WWW::Crawler::Mojo->new;
    $bot->init;
    $bot->scrape($res, WWW::Crawler::Mojo::Job->new(resolved_uri => 'http://example.com/'));
    
    my $job;
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, '/index1.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index1.html?foo=default', 'right url';
    is $job->method, 'GET', 'right method';
    is_deeply $job->tx_params, undef, 'right params';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, '/index2.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index2.html', 'right url';
    is $job->method, 'POST', 'right method';
    is_deeply $job->tx_params->to_hash, {foo => 'foo'}, 'right params';
    $job = shift @{$bot->{queue}};
    is $job->literal_uri, '/index2.html', 'right url';
    is $job->resolved_uri, 'http://example.com/index2.html', 'right url';
    is $job->method, 'POST', 'right method';
    is_deeply $job->tx_params->to_hash, {bar => 'bar'}, 'right params';
    $job = shift @{$bot->{queue}};
    is $job, undef, 'no more urls';
}

