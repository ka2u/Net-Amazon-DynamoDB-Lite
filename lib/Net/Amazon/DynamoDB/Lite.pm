package Net::Amazon::DynamoDB::Lite;
use 5.008001;
use strict;
use warnings;

our $VERSION = "0.01";

use Carp;
use Furl;
use HTTP::Request;
use JSON;
use Moo;
use POSIX qw(setlocale LC_TIME strftime);
use Scalar::Util qw(reftype);
use WebService::Amazon::Signature::v4;

has signature => (
    is => 'lazy',
);

has scope => (
    is => 'lazy',
);

has ua => (
    is => 'lazy',
);

has uri => (
    is => 'lazy',
);

has access_key => (
    is => 'ro',
);

has secret_key => (
    is => 'ro',
);

has region => (
    is => 'ro',
);

has api_version => (
    is => 'ro',
    default => sub {
        '20120810',
    },
);

has ca_path => (
    is => 'rw',
    default => sub {
        '/etc/ssl/certs',
    },
);

has connection_timeout => (
    is => 'rw',
    default => sub {
        1,
    },
);

has json => (
    is => 'rw',
    default => sub {
        JSON->new,
    },
);

sub _build_signature {
    my ($self) = @_;
    my $locale = setlocale(LC_TIME);
    setlocale(LC_TIME, "C");
    my $v4 = WebService::Amazon::Signature::v4->new(
        scope => $self->scope,
        access_key => $self->access_key,
        secret_key => $self->secret_key,
    );
    setlocale(LC_TIME, $locale);
    $v4;
}

sub _build_scope {
    my ($self) = @_;
    join '/', strftime('%Y%m%d', gmtime), $self->region, qw(dynamodb aws4_request);
}

sub _build_ua {
    my ($self) = @_;

    my $ua = Furl->new(
        agent => 'Net::Amazon::DynamoDB::Lite v0.01',
        timeout => $self->connection_timeout,
        ssl_opts => {
            SSL_ca_path => $self->ca_path,
        },
    );
}

sub _build_uri {
    my ($self) = @_;
    URI->new('https://dynamodb.' . $self->region . '.amazonaws.com/');
}

sub make_request {
    my ($self, $target, $content) = @_;

    my $req = HTTP::Request->new(
        POST => $self->uri,
    );
    my $locale = setlocale(LC_TIME);
    setlocale(LC_TIME, "C");
    $req->header(host => $self->uri->host);
    my $http_date = strftime('%a, %d %b %Y %H:%M:%S %Z', localtime);
    my $amz_date = strftime('%Y%m%dT%H%M%SZ', gmtime);
    $req->header(Date => $http_date);
    $req->header('x-amz-date' => $amz_date);
    $req->header('x-amz-target' => 'DynamoDB_' . $self->api_version . ".$target" );
    $req->header('content-type' => 'application/x-amz-json-1.0');
    $content = $self->json->encode($content);
    $req->content($content);
    $req->header('Content-Length' => length($content));
    $self->signature->from_http_request($req);
    $req->header(Authorization => $self->signature->calculate_signature);
    setlocale(LC_TIME, $locale);
    return $req;
}

sub list_tables {
    my ($self, $content) = @_;

    $content = {} unless $content;
    my $req = $self->make_request('ListTables', $content);
    my $res = $self->ua->request($req);
    my $decoded;
    eval {
        $decoded = $self->json->decode($res->content);
    };
    Carp::croak $res->content if $@;
    return $decoded->{TableNames};
}

sub put_item {
    my ($self, $content) = @_;

    Carp::croak "Item required." unless $content->{Item};
    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('PutItem', $content);
    my $res = $self->ua->request($req);
    if ($res->is_success) {
        return 1;
    } else {
        Carp::croak $res->content;
    }
}

sub get_item {
    my ($self, $content) = @_;

    Carp::croak "Key required." unless $content->{Key};
    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('GetItem', $content);
    my $res = $self->ua->request($req);
    my $decoded;
    eval {
        $decoded = $self->json->decode($res->content);
    };
    Carp::croak $res->content if $@;
    return _except_type($decoded->{Item});
}

sub update_item {
    my ($self, $content) = @_;

    Carp::croak "Key required." unless $content->{Key};
    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('UpdateItem', $content);
    my $res = $self->ua->request($req);
    if ($res->is_success) {
        return 1;
    } else {
        Carp::croak $res->content;
    }
}

sub delete_item {
    my ($self, $content) = @_;

    Carp::croak "Key required." unless $content->{Key};
    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('DeleteItem', $content);
    my $res = $self->ua->request($req);
    if ($res->is_success) {
        return 1;
    } else {
        Carp::croak $res->content;
    }
}

sub create_table {
    my ($self, $content) = @_;

    Carp::croak "AttributeDefinitions required." unless $content->{AttributeDefinitions};
    Carp::croak "KeySchema required." unless $content->{KeySchema};
    Carp::croak "ProvisionedThroughput required." unless $content->{ProvisionedThroughput};
    Carp::croak "TableName required." unless $content->{TableName};

    my $req = $self->make_request('CreateTable', $content);
    my $res = $self->ua->request($req);
    my $decoded = $self->json->decode($res->content);
    if ($res->is_success) {
        return 1;
    } else {
        Carp::croak "__type : " . $decoded->{__type} . " message : "
              . $decoded->{Message};
    }
}

sub delete_table {
    my ($self, $content) = @_;

    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('DeleteTable', $content);
    my $res = $self->ua->request($req);
    if ($res->is_success) {
        return 1;
    } else {
        Carp::croak $res->content;
    }
}

sub describe_table {
    my ($self, $content) = @_;

    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('DescribeTable', $content);
    my $res = $self->ua->request($req);
    my $decoded;
    eval {
        $decoded = $self->json->decode($res->content);
    };
    Carp::croak $res->content if $@;
    return $decoded->{Table};
}

sub update_table {
    my ($self, $content) = @_;

    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('UpdateTable', $content);
    my $res = $self->ua->request($req);
    if ($res->is_success) {
        return 1;
    } else {
        Carp::croak $res->content;
    }
}

sub query {
    my ($self, $content) = @_;

    Carp::croak "TableName required." unless $content->{TableName};
    my $req = $self->make_request('Query', $content);
    my $res = $self->ua->request($req);

    my $decoded = $self->json->decode($res->content);
    if ($res->is_success) {
        return _except_type($decoded->{Items});
    } else {
        Carp::croak "__type : " . $decoded->{__type} . " message : "
              . $decoded->{Message};
    }
}

sub scan {
    my ($self, $table, $filter_expressions, $expression_attribute_values) = @_;

    my $content = {
        TableName => $table,
        FilterExpression => $filter_expressions,
    };

    foreach my $k (keys %{$expression_attribute_values}) {
        my $v = $expression_attribute_values->{$k};
        $content->{ExpressionAttributeValues} = { $k => {_type_and_value($v)} };
    }

    my $req = $self->make_request('Scan', $content);
    my $res = $self->ua->request($req);
    my $decoded = $self->json->decode($res->content);
    if ($res->is_success) {
        return _except_type($decoded->{Items});
    } else {
        Carp::croak "__type : " . $decoded->{__type} . " message : "
              . $decoded->{Message};
    }
}

sub batch_get_item {
    my ($self, $request_items) = @_;

    my $content;
    foreach my $k (keys %{$request_items}) {
        my $v = $request_items->{$k};
        foreach my $l (@{$v}) {
            my ($key) = keys %{$l};
            push @{$content->{RequestItems}->{$k}->{Keys}},
              { $key => {_type_and_value($l->{$key})} };
        }
    }

    my $req = $self->make_request('BatchGetItem', $content);
    my $res = $self->ua->request($req);
    my $decoded = $self->json->decode($res->content);
    if ($res->is_success) {
        my $res;
        for my $k (keys $decoded->{Responses}) {
            push @{$res}, {$k => _except_type($decoded->{Responses}->{$k})};
        }
        return $res;
    } else {
        Carp::croak "__type : " . $decoded->{__type} . " message : "
              . $decoded->{Message};
    }
}

sub batch_write_item {
    my ($self, $mode, $request_items) = @_;

    my $content;
    if ($mode eq 'PUT') {
        for my $table (keys %{$request_items}) {
            my $v = $request_items->{$table};
            for my $l (@{$v}) {
                my $put = {};
                for my $key (keys %{$l}) {
                    $put->{PutRequest}->{Item}->{$key} = {_type_and_value($l->{$key})};
                }
                push @{$content->{RequestItems}->{$table}}, $put;
            }
        }
    } elsif ($mode eq 'DELETE') {
        for my $table (keys %{$request_items}) {
            my $v = $request_items->{$table};
            for my $l (@{$v}) {
                my $delete = {};
                for my $key (keys %{$l}) {
                    $delete->{DeleteRequest}->{Key}->{$key} = {_type_and_value($l->{$key})};
                }
                push @{$content->{RequestItems}->{$table}}, $delete;
            }
        }
    }

    my $req = $self->make_request('BatchWriteItem', $content);
    my $res = $self->ua->request($req);
}

sub _type_for_value {
    my $v = shift;
    if(my $ref = reftype($v)) {
        # An array maps to a sequence
        if($ref eq 'ARRAY') {
            my $flags = B::svref_2object(\$v)->FLAGS;
            # Any refs mean we're sending binary data
            return 'BS' if grep ref($_), @$v;
            # Any stringified values => string data
            return 'SS' if grep $_ & B::SVp_POK, map B::svref_2object(\$_)->FLAGS, @$v;
            # Everything numeric? Send as a number
            return 'NS' if @$v == grep $_ & (B::SVp_IOK | B::SVp_NOK), map B::svref_2object(\$_)->FLAGS, @$v;
            # Default is a string sequence
            return 'SS';
        } else {
            return 'B';
        }
    } else {
        my $flags = B::svref_2object(\$v)->FLAGS;
        return 'S' if $flags & B::SVp_POK;
        return 'N' if $flags & (B::SVp_IOK | B::SVp_NOK);
        return 'S';
    }
}

sub _type_and_value {
    my $v = shift;
    my $type = _type_for_value($v);
    return $type, "$v" unless my $ref = ref $v;
    return $type, [ map "$_", @$v ] if $ref eq 'ARRAY';
    return $type, { map {; $_ => ''.$v->{$_} } keys %$v } if $ref eq 'HASH';
    return $type, "$v";
}

sub _except_type {
    my $v = shift;
    my $res;
    if (ref $v eq 'HASH') {
        for my $k (keys %{$v}) {
            my $with_type = $v->{$k};
            my ($k2) = keys %{$with_type};
            $res->{$k} = $with_type->{$k2};
        }
    } elsif (ref $v eq 'ARRAY') {
        for my $w (@{$v}) {
            my $with_out_type;
            for my $k (keys %{$w}) {
                my $with_type = $w->{$k};
                my ($k2) = keys %{$with_type};
                $with_out_type->{$k} = $with_type->{$k2};
            }
            push @{$res}, $with_out_type;
        }
    }
    return $res;
}



1;
__END__

=encoding utf-8

=head1 NAME

Net::Amazon::DynamoDB::Lite - It's new $module

=head1 SYNOPSIS

    use Net::Amazon::DynamoDB::Lite;

=head1 DESCRIPTION

Net::Amazon::DynamoDB::Lite is ...

=head1 METHODS

=head2 list_tables

    {
        "ExclusiveStartTableName" => "string",
        "Limit" => "number"
    }

=head2 put_item

    {
        "ConditionExpression" => "string",
        "ConditionalOperator" => "string",
        "Expected" => {
            "string" => {
                "AttributeValueList": [
                {
                    "B" => "blob",
                    "BOOL" => "boolean",
                    "BS" => [
                        "blob"
                    ],
                    "L" => [
                        AttributeValue
                    ],
                    "M" => {
                        "string" => AttributeValue
                    },
                    "N" => "string",
                    "NS" => [
                        "string"
                    ],
                    "NULL" => "boolean",
                    "S" => "string",
                    "SS" => [
                        "string"
                    ]
                }
            ],
                "ComparisonOperator" => "string",
                "Exists" => "boolean",
                "Value" => {
                    "B" => "blob",
                    "BOOL" => "boolean",
                    "BS" => [
                        "blob"
                    ],
                    "L" => [
                        AttributeValue
                    ],
                    "M" => {
                        "string" => AttributeValue
                    },
                    "N" => "string",
                    "NS" => [
                        "string"
                    ],
                    "NULL" => "boolean",
                    "S" => "string",
                    "SS" => [
                        "string"
                    ]
                }
            }
        },
        "ExpressionAttributeNames" => {
            "string" => "string"
        },
        "ExpressionAttributeValues" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "Item" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "ReturnConsumedCapacity" => "string",
        "ReturnItemCollectionMetrics" => "string",
        "ReturnValues" => "string",
        "TableName" => "string"
    }

=head2 get_item

    {
        "AttributesToGet" => [
            "string"
        ],
        "ConsistentRead" => "boolean",
        "ExpressionAttributeNames" => {
            "string" => "string"
        },
        "Key" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "ProjectionExpression" => "string",
        "ReturnConsumedCapacity" => "string",
        "TableName" => "string"
    }

=head2 update_item

    {
        "AttributeUpdates" => {
            "string" => {
                "Action" => "string",
                "Value" => {
                    "B" => "blob",
                    "BOOL" => "boolean",
                    "BS" => [
                        "blob"
                    ],
                    "L" => [
                        AttributeValue
                    ],
                    "M" => {
                        "string" => AttributeValue
                    },
                    "N" => "string",
                    "NS" => [
                        "string"
                    ],
                    "NULL" => "boolean",
                    "S" => "string",
                    "SS" => [
                        "string"
                    ]
                }
            }
        },
        "ConditionExpression" => "string",
        "ConditionalOperator" => "string",
        "Expected" => {
            "string" => {
                "AttributeValueList" => [
                    {
                        "B" => "blob",
                        "BOOL" => "boolean",
                        "BS" => [
                            "blob"
                        ],
                        "L" => [
                            AttributeValue
                        ],
                        "M" => {
                            "string" => AttributeValue
                        },
                        "N" => "string",
                        "NS" => [
                            "string"
                        ],
                        "NULL" => "boolean",
                        "S" => "string",
                        "SS" => [
                            "string"
                        ]
                    }
                ],
                "ComparisonOperator" => "string",
                "Exists" => "boolean",
                "Value" => {
                    "B" => "blob",
                    "BOOL" => "boolean",
                    "BS" => [
                        "blob"
                    ],
                    "L" => [
                        AttributeValue
                    ],
                    "M" => {
                        "string" => AttributeValue
                    },
                    "N" => "string",
                    "NS" => [
                        "string"
                    ],
                    "NULL" => "boolean",
                    "S" => "string",
                    "SS" => [
                        "string"
                    ]
                }
            }
        },
        "ExpressionAttributeNames" => {
            "string" => "string"
        },
        "ExpressionAttributeValues" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "Key" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "ReturnConsumedCapacity" => "string",
        "ReturnItemCollectionMetrics" => "string",
        "ReturnValues" => "string",
        "TableName" => "string",
        "UpdateExpression" => "string"
    }

=head2 delete_item

    {
        "ConditionExpression" => "string",
        "ConditionalOperator" => "string",
        "Expected" => {
            "string" => {
                "AttributeValueList" => [
                    {
                        "B" => "blob",
                        "BOOL" => "boolean",
                        "BS" => [
                            "blob"
                        ],
                        "L" => [
                            AttributeValue
                        ],
                        "M" => {
                            "string" => AttributeValue
                        },
                        "N" => "string",
                        "NS" => [
                            "string"
                        ],
                        "NULL" => "boolean",
                        "S" => "string",
                        "SS" => [
                            "string"
                        ]
                    }
                ],
                "ComparisonOperator" => "string",
                "Exists" => "boolean",
                "Value" => {
                    "B" => "blob",
                    "BOOL" => "boolean",
                    "BS" => [
                        "blob"
                    ],
                    "L" => [
                        AttributeValue
                    ],
                    "M" => {
                        "string" => AttributeValue
                    },
                    "N" => "string",
                    "NS" => [
                        "string"
                    ],
                    "NULL" => "boolean",
                    "S" => "string",
                    "SS" => [
                        "string"
                    ]
                }
            }
        },
        "ExpressionAttributeNames" => {
            "string" => "string"
        },
        "ExpressionAttributeValues" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "Key" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" =>  AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "ReturnConsumedCapacity" => "string",
        "ReturnItemCollectionMetrics" => "string",
        "ReturnValues" => "string",
        "TableName" => "string"
    }

=head2 create_table

    {
        "AttributeDefinitions" => [
            {
                "AttributeName" => "string",
                "AttributeType" => "string",
            }
        ],
        "GlobalSecondaryIndexes" => [
            {
                "IndexName" => "string",
                "KeySchema" => [
                    {
                        "AttributeName" => "string",
                        "KeyType" => "string"
                    }
                ],
                "Projection" => {
                    "NonKeyAttributes" => [
                        "string"
                    ],
                    "ProjectionType" => "string"
                },
                "ProvisionedThroughput" => {
                    "ReadCapacityUnits" => "number",
                    "WriteCapacityUnits" => "number"
                }
            }
        ],
        "KeySchema" => [
            {
                "AttributeName" => "string",
                "KeyType" => "string"
            }
        ],
        "LocalSecondaryIndexes" => [
            {
                "IndexName" => "string",
                "KeySchema" => [
                    {
                        "AttributeName" => "string",
                        "KeyType" => "string"
                    }
                ],
                "Projection" => {
                     "NonKeyAttributes" => [
                         "string"
                     ],
                     "ProjectionType" => "string"
                 }
            }
        ],
        "ProvisionedThroughput" => {
            "ReadCapacityUnits" => "number",
            "WriteCapacityUnits" => "number"
        },
        "TableName" => "string"
    }

=head2 delete_table

    {
        "TableName" => "string"
    }

=head2 describe_table

    {
        "TableName" => "string"
    }

=head2 update_table

    {
        "AttributeDefinitions" => [
            {
                "AttributeName" => "string",
                "AttributeType" => "string"
            }
        ],
        "GlobalSecondaryIndexUpdates" => [
            {
                "Create" => {
                    "IndexName" => "string",
                    "KeySchema" => [
                        {
                            "AttributeName" => "string",
                            "KeyType" => "string"
                        }
                    ],
                    "Projection" => {
                        "NonKeyAttributes" => [
                            "string"
                        ],
                        "ProjectionType" =>  "string"
                     },
                    "ProvisionedThroughput" => {
                        "ReadCapacityUnits" => "number",
                        "WriteCapacityUnits" => "number"
                    }
                },
                "Delete" => {
                    "IndexName" => "string"
                },
                "Update" => {
                    "IndexName" => "string",
                    "ProvisionedThroughput" => {
                        "ReadCapacityUnits" => "number",
                        "WriteCapacityUnits" => "number"
                    }
                }
           }
        ],
        "ProvisionedThroughput" => {
            "ReadCapacityUnits" => "number",
            "WriteCapacityUnits" => "number"
        },
        "TableName" => "string"
    }

=head2 query

    {
        "AttributesToGet" => [
            "string"
        ],
        "ConditionalOperator" => "string",
        "ConsistentRead" => "boolean",
        "ExclusiveStartKey" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                 ],
                 "M" => {
                     "string" => AttributeValue
                 },
                 "N" => "string",
                 "NS" => [
                     "string"
                 ],
                 "NULL" => "boolean",
                 "S" => "string",
                 "SS" => [
                     "string"
                 ]
            }
        },
        "ExpressionAttributeNames" => {
           "string" => "string"
        },
        "ExpressionAttributeValues" => {
            "string" => {
                "B" => "blob",
                "BOOL" => "boolean",
                "BS" => [
                    "blob"
                ],
                "L" => [
                    AttributeValue
                ],
                "M" => {
                    "string" => AttributeValue
                },
                "N" => "string",
                "NS" => [
                    "string"
                ],
                "NULL" => "boolean",
                "S" => "string",
                "SS" => [
                    "string"
                ]
            }
        },
        "FilterExpression" => "string",
        "IndexName" => "string",
        "KeyConditionExpression" => "string",
        "KeyConditions" => {
            "string" => {
                "AttributeValueList" => [
                    {
                        "B" => "blob",
                        "BOOL" => "boolean",
                        "BS" => [
                            "blob"
                        ],
                        "L" => [
                            AttributeValue
                        ],
                        "M" => {
                             "string" => AttributeValue
                        },
                        "N" => "string",
                        "NS" => [
                            "string"
                        ],
                        "NULL" => "boolean",
                        "S" => "string",
                        "SS" => [
                            "string"
                        ]
                    }
                ],
                "ComparisonOperator" => "string"
            }
        },
        "Limit" => "number",
        "ProjectionExpression" => "string",
        "QueryFilter" => {
            "string" => {
                "AttributeValueList" => [
                    {
                        "B" => "blob",
                        "BOOL" => "boolean",
                        "BS" => [
                            "blob"
                        ],
                        "L" => [
                            AttributeValue
                        ],
                        "M" => {
                            "string" => AttributeValue
                        },
                        "N" => "string",
                        "NS" => [
                            "string"
                        ],
                        "NULL" => "boolean",
                        "S" => "string",
                        "SS" => [
                            "string"
                        ]
                    }
                ],
                "ComparisonOperator" => "string"
            }
        },
        "ReturnConsumedCapacity" => "string",
        "ScanIndexForward" => "boolean",
        "Select" => "string",
        "TableName" => "string"
    }



=head1 LICENSE

Copyright (C) Kazuhiro Shibuya.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kazuhiro Shibuya E<lt>stevenlabs at gmail.comE<gt>

=cut

