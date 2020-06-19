# Visualizing data from AWS Config Snapshots and VPC Flow Logs using ElasticSearch & Kibana.

![](/images/AWS_Config.png)

## Author
### Li-Yen Tseng
This project also integrates multiple methods from some blog posts and other projects. The original author and references are listed below.
- [awslabs/aws-config-to-elasticsearch](https://github.com/awslabs/aws-config-to-elasticsearch) by Vladimir Budilov
- [Getting AWS logs from S3 using Filebeat and the Elastic Stack](https://www.elastic.co/blog/getting-aws-logs-from-s3-using-filebeat-and-the-elastic-stack) by [Kaiyan Sheng](https://www.elastic.co/blog/author/kaiyan-sheng)
- [How to Optimize and Visualize Your Security Groups](https://aws.amazon.com/blogs/security/how-to-optimize-and-visualize-your-security-groups) by Guy Denney

### What problem does this app solve?
You have a lot of resources in your AWS account and want to search and visualize them. For example, you'd like to know your EC2 Avaiability Zone distribution or how many EC2 instances are using a particular Security Group. For monitoring VPC network, you'd like to know where does the REJECTED flows come from, or which ACCEPTED flow is allowed by which Security Group.

### What does this app do?
It will ingest your AWS Config Snapshots into ElasticSearch for further analysis with Kibana. Please
refer to [this blog post](https://aws.amazon.com/blogs/developer/how-to-analyze-aws-config-snapshots-with-elasticsearch-and-kibana/)
for a more in-depth explanation of this solution.

You should configure VPC flow logs with destination type "S3" and create a S3 ObjectCreate event sending logs to SQS. Then we use Filebeat to pull logs from SQS and Filebeat will send processed data to Elasticsearch.

## How to use
### Getting the code
```
git clone https://github.com/LYTzeng/aws-config-to-elasticsearch.git
```

### AWS Config snapshots to Elasticsearch
#### Prerequisites
* Python 2.7
* An ELK stack, up and running **(At least Elasticsearch 7.6 and Kibana 7.6 installed)**
* Install the required packages. The requirements.txt file is included with this repo.
```
pip install -r ./requirements.txt
```

#### The command
```bash
./esingest.py
usage: esingest.py [-h] [--region REGION] --destination DESTINATION [--verbose]

```

1. Let's say that you have your ElasticSearch node running on localhost:9200 and you want to import only your us-east-1 snapshot, then you'd run the following command:
```bash
./esingest.py -d localhost:9200 -r us-east-1
```

2. If you want to import Snapshots from all of your AWS Config-enabled regions, run the command without the '-r' parameter:
```bash
./esingest.py -d localhost:9200
```
3. To run the command in verbose mode, use the -v parameter
```bash
./esingest.py -v -d localhost:9200 -r us-east-1
```

### Kibana Dashboard
#### Create an Index Pattern
1. Log in to Kibana. In the homepage, in the left toolbar, click **Management** (the cog icon) then select **Index Patterns**. Click the **Create index pattern** button. For index pattern, enter `*` to use this wildcard. Click **Next step**.

2. Under **Time Filter field name**, select **snapshotTimeIso**. Click the **Create Index Pattern** button.

#### Import the AWS Config Dashboard
1. In the left toolbar, click **Management**. Click on **Saved Objects**. Click **Import** on the upper right then select the file `kibana/aws_config_dashboard.ndjson` in this repository, and click **Import**.

2. You should see a new dashboard named **AWS Config** under the list of *Saved Objects*. Click on the dashboard **AWS Config** and have fun. 😎

### Cleanup
> :warning:
> DON'T RUN THESE COMMANDS IF YOU DON'T WANT TO LOSE EVERYTHING IN YOUR ELASTICSEARCH NODE!

> :warning: _THIS COMMAND WILL ERASE EVERYTHING FROM YOUR ES NODE --- BE CAREFUL BEFORE RUNNING_
:::
```bash
curl -XDELETE localhost:9200/_all
```

In order to avoid losing all of your data, you can just iterate over all of your indexes and delete them that way. The below command will print out all of your indexes that contain 'aws::'. You can then run a DELETE on just these indexes.
```bash
curl 'localhost:9200/_cat/indices' | awk '{print $3}' | grep "aws-"
```

Also delete the template which allows for creationg of a 'raw' string value alongside every 'analyzed' one
```bash
curl -XDELETE localhost:9200/_template/configservice
```
