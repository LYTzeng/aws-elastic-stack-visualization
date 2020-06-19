# Visualizing data from AWS Config Snapshots and VPC Flow Logs using ElasticSearch & Kibana.

![The page should have displayed a picture here!](/images/AWS_Config.png)

![The page should have displayed a picture here!](/images/Rejected_VPC_Flow.png)

## Author
### Li-Yen Tseng
This project also integrates multiple methods/code from some blog posts and other projects. The original author and references are listed below.
- [awslabs/aws-config-to-elasticsearch](https://github.com/awslabs/aws-config-to-elasticsearch) by Vladimir Budilov
- [Getting AWS logs from S3 using Filebeat and the Elastic Stack](https://www.elastic.co/blog/getting-aws-logs-from-s3-using-filebeat-and-the-elastic-stack) by [Kaiyan Sheng](https://www.elastic.co/blog/author/kaiyan-sheng)
- [How to Optimize and Visualize Your Security Groups](https://aws.amazon.com/blogs/security/how-to-optimize-and-visualize-your-security-groups) by Guy Denney

### Project Architecture Diagram
![The page should have displayed a picture here!](/images/architecture.png)

### What problem does this app solve?
You have a lot of resources in your AWS account and want to search and visualize them. For example, you'd like to know your EC2 Avaiability Zone distribution or how many EC2 instances are using a particular Security Group. 

For monitoring VPC network, AWS only provides VPC Flow Logs. Based on Flow Log, you'd like to know where does the REJECTED flows come from, or which ACCEPTED flow is allowed by which Security Group.

### What does this app do?
It will ingest your AWS Config Snapshots into ElasticSearch for further analysis with Kibana. Please
refer to [this blog post](https://aws.amazon.com/blogs/developer/how-to-analyze-aws-config-snapshots-with-elasticsearch-and-kibana/)
for a more in-depth explanation of this solution.

**You should configure VPC flow logs with destination type "S3" and create a S3 ObjectCreate event sending logs to SQS**. Then we use Filebeat to pull logs from SQS and Filebeat will send processed data to Elasticsearch.

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

#### Kibana Dashboard
##### Create an Index Pattern
1. Log in to Kibana. In the homepage, in the left toolbar, click **Management** (the cog icon) then select **Index Patterns**. Click the **Create index pattern** button. For index pattern, enter `*` to use this wildcard. Click **Next step**.

2. Under **Time Filter field name**, select **snapshotTimeIso**. Click the **Create Index Pattern** button.

##### Import the AWS Config Dashboard
1. In the left toolbar, click **Management**. Click on **Saved Objects**. Click **Import** on the upper right then select the file `kibana/aws_config_dashboard.ndjson` in this repository, and click **Import**.

2. You should see a new dashboard named **AWS Config** under the list of *Saved Objects*. Click on the dashboard **AWS Config** and have fun. 😎

***

### Visualizing Flow Logs
#### Import dashboards to Kibana
In **Saved Objects**, import `kibana/accepted_vpc-flow.ndjson` and `kibana/rejected_vpc_flow.ndjson`. The steps is the same as you import the *AWS Config Dashboard*.

#### Install and Configure Filebeat
1. The easiest way to install Filebeat is to use APT or YUM repositories. See [the doc](https://www.elastic.co/guide/en/beats/filebeat/current/setup-repositories.html) for more info. In this project we use Filebeat **7.7.1**.
```bash
sudo apt update && sudo apt install -y filebeat=7.7.1
```
2. Enable the Fliebeat AWS module.
```bash
filebeat modules enable aws
```
You can check a list of enabled modules by running `filebeat modules list`.

3. Edit Filebeat config file which is `/etc/filebeat/filebeat.yml`. Configure your Elasticsearch output.
```yaml
output.elasticsearch:
  # Array of hosts to connect to.
  hosts: ["172.31.64.162:9200"]
```

4. Edit the AWS module config file `/etc/filebeat/modules.d/aws.yml`. Under `vpcflow`, make sure it's enabled and configured. The below config assumes that Filebeat was installed on a EC2 with IAM instance profile/role attached so we only need to specify the role ARN. Also you need to set up an SQS queue for this.
```yaml
vpcflow:
    enabled: true
    # AWS SQS queue url
    var.queue_url: https://sqs.us-west-2.amazonaws.com/197856344428/S3-flow-log
    var.role_arn: arn:aws:iam::197856344428:role/ansilbe-power-user
```

5. Start the service.
```bash
sudo systemctl start filebeat
```

6. Log in to Kibana. Create a **Index Pattern** with pattern `filebeat-7.7.1-*`. The dashboard should show visualizations.

***

### Optimize and Visualizing Security Groups
Execute the script `sgremediate.sh`. 
Command usage:
```
./sgremediate.sh KIBANA_URL PROFILE VPC_ID > index.html
```
Say if you have Kibana running at `ec2-203-0-113-87.us-west-2.compute.amazonaws.com:5601`, and a VPC id in the region configured in your AWS CLI `default` profile is `vpc-9e2d12e4`, run the following command:
```bash
./sgremediate.sh ec2-203-0-113-87.us-west-2.compute.amazonaws.com:5601 default vpc-9e2d12e4 > index.html
```
Then an HTML webpage will be generated containing used/unused Security Group IDs. Click on an ID and it will link you to the dashboard showing all interfaces, dest port, etc. related to this Security Group.
![The page should have displayed a picture here!](/images/index.html.png)

You'll see the KQL query was automatically filled in the filter. Below will show only dest port/countries related to this Security Group.
![The page should have displayed a picture here!](/images/filtered-dashboard.png)

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
