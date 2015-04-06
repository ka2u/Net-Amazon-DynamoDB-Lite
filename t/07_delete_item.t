use strict;
use Test::More 0.98;
use Time::Piece;
use Net::Amazon::DynamoDB::Lite;
use URI;

my $dynamo = Net::Amazon::DynamoDB::Lite->new(
    region     => 'ap-northeast-1',
    access_key => 'XXXXXXXXXXXXXXXXX',
    secret_key => 'YYYYYYYYYYYYYYYYY',
    uri => URI->new('http://localhost:8000'),
);

eval {
    $dynamo->list_tables;
};

my $t = localtime;
my $table = 'test_' . $t->epoch;
SKIP: {
    skip $@, 2 if $@;
    my $t = localtime;
    $dynamo->create_table($table, 5, 5, {id => 'HASH'}, {id => 'S'});
    $dynamo->put_item($table, {id => "12345678", last_update => "2015-03-30 10:24:00"});
    $dynamo->put_item($table, {id => "99999999", last_update => "2015-03-31 10:24:00"});
    my $delete_res = $dynamo->delete_item($table, {id => "99999999"});
    ok $delete_res;
    my $get_res = $dynamo->get_item('test', {id => "99999999"});
    is $get_res, undef;
    $dynamo->delete_table($table);
}


done_testing;
