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
    skip $@, 3 if $@;
    my $create_res = $dynamo->create_table({
        "AttributeDefinitions" => [
            {
                "AttributeName" => "id",
                "AttributeType" => "S",
            }
        ],
        "KeySchema" => [
            {
                "AttributeName" => "id",
                "KeyType" => "HASH"
            }
        ],
        "ProvisionedThroughput" => {
            "ReadCapacityUnits" => 5,
            "WriteCapacityUnits" => 5,
        },
        "TableName" => $table,
    });
    ok $create_res;
    $dynamo->put_item($table, {id => "11111", last_update => "2015-03-30 18:41:23"});
    $dynamo->put_item($table, {id => "22222", last_update => "2015-03-30 18:41:23"});
    $dynamo->put_item($table, {id => "33333", last_update => "2015-03-30 18:41:23"});
    my $res = $dynamo->scan($table, "last_update = :val", {":val" => "2015-03-30 18:41:23"});
    is scalar @{$res}, 3;
    $dynamo->delete_table($table);
}

done_testing;
