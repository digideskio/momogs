#!/usr/bin/env ruby
require 'rubygems'
require 'json'
require 'pp'
require 'time'
require 'date'
require 'mongo'
require 'getGSResponse'
require 'getGSRepliesForTopic'
require 'getGSTagsForTopic'
require 'computeSyntheticAndInsertUpdateTopic'

MONGO_HOST = ENV["MONGO_HOST"]
raise(StandardError,"Set Mongo hostname in  ENV: 'MONGO_HOST'") if !MONGO_HOST
MONGO_PORT = ENV["MONGO_PORT"]
raise(StandardError,"Set Mongo port in  ENV: 'MONGO_PORT'") if !MONGO_PORT
MONGO_USER = ENV["MONGO_USER"]
raise(StandardError,"Set Mongo user in  ENV: 'MONGO_USER'") if !MONGO_USER
MONGO_PASSWORD = ENV["MONGO_PASSWORD"]
raise(StandardError,"Set Mongo user in  ENV: 'MONGO_PASSWORD'") if !MONGO_PASSWORD

db = Mongo::Connection.new(MONGO_HOST, MONGO_PORT.to_i).db("gs")
auth = db.authenticate(MONGO_USER, MONGO_PASSWORD)
if !auth
  raise(StandardError, "Couldn't authenticate, exiting")
  exit
end

topicsColl = db.collection("topics")

if ARGV.length < 4
  puts "usage: #{$0} yyyy mm dd [tag]"
  exit
end

tag = ARGV[3]
metrics_start = Time.utc(ARGV[0], ARGV[1], ARGV[2], 0, 0)
metrics_stop = Time.utc(ARGV[0], ARGV[1], ARGV[2], 23, 59, 59)
metrics_stop += 1

topic_page = 0
topic_before_start_time = false
verbose_logging = false
while true
  topic_page += 1
  $stderr.printf("HTTP GET page:%d of companies/mozilla_messaging/products/mozilla_thunderbird/topics.json\n", topic_page)
  topics = getResponse("companies/mozilla_messaging/products/mozilla_thunderbird/topics.json", 
    {:sort => "recently_created", :page => topic_page, :limit => 30, :tag => tag})
  topics["data"].each do|topic|
    last_active_at = Time.parse(topic["last_active_at"])
    last_active_at = last_active_at.utc
    printf(STDERR, "TOPIC last_active_at:%s\n", last_active_at)
    created_at = Time.parse(topic["created_at"])
    created_at = created_at.utc
    printf(STDERR, "TOPIC created_at:%s\n", last_active_at)
    # JSON only transports string times so convert time to Unix time before putting it into mongo
    topic.delete("last_active_at") 
    topic["last_active_at"] = last_active_at
    topic.delete("created_at") 
    topic["created_at"] = created_at
    if topic["is_closed"]
      closed_at = Time.parse(topic["closed_at"])
      closed_at = closed_at.utc
      topic.delete("closed_at")
      topic["closed_at"] = closed_at
    end

    if (created_at <=> metrics_start) == -1 
      printf(STDERR, "ending getGSTopicsAfter\n")
      topic_before_start_time = true
      break
    end    
    if (created_at <=> metrics_stop) == 1
      printf(STDERR, "topic created after METRICS STOP so skipping getGSTopicsAfter\n")
      next
    end
    $stderr.printf("url:%s tagged:%s\n", topic["at_sfn"], tag)
    topic["tags_array"] = []
    topic["tag_id_array"] = []
    topic["reply_id_array"] = []
    topic["reply_array"] = []
    topic["fulltext"] = ""
    topic["fulltext_with_tags"] = ""
    topic["tags_str"] = ""
    topic["synthetic_status_journal"] = []
    if verbose_logging
      printf(STDERR, "START*** of topic\n")
      PP::pp(topic,$stderr)
      printf(STDERR, "\nEND*** of topic\n")
    end
    topic_text = topic["subject"].downcase + " " + topic["content"].downcase
    reply_count = topic["reply_count"]  
    printf(STDERR, "reply_count:%d\n", reply_count)
    topic["reply_count"] = reply_count
    topic["fulltext"] = topic_text
    topic["fulltext_with_tags"] = topic_text
    if reply_count != 0
      topic = getGSRepliesForTopic(topic, reply_count, verbose_logging)          
    end # if reply_count != 0
    topic = getGSTagsForTopic(topic, verbose_logging)      
    id = topic["id"]
    computeSyntheticAttributesAndInsertUpdateTopic(topic, id, topicsColl)    
  end # topics["data"].each do|topic|
  if topic_before_start_time
    break
  end
end # while
 
