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
    $dynamo->create_table({
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
    my $put_res = $dynamo->put_item($table, {id => "12345678", last_update => "2015-03-30 10:24:00"});
    ok $put_res;
    my $get_res = $dynamo->get_item($table, {id => "12345678"});
    is_deeply $get_res, {
        'last_update' => '2015-03-30 10:24:00',
        'id' => '12345678',
    };
    $dynamo->delete_table($table);
}


done_testing;
