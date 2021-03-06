#!/usr/bin/env ruby
require 'rubygems'
require 'json'
require 'net/http'
require 'pp'
require 'awesome_print'
require 'time'
require 'date'

def getResponse(url)
  http = Net::HTTP.new("api.getsatisfaction.com",80)
  url = "/" + url 
  try1 = true
  begin
    resp, data = http.get(url, nil)
  rescue Timeout::Error => e
    if try1
      $stderr.printf("retrying after HTTP GET Timeout EXCEPTION, url:%s\n",url)
      try1 = false
      retry
    else
      $stderr.printf("2nd HTTP GET Failed with a Timeout EXCEPTION, url:%s TERMINATING\n",url)
      raise
    end
  end
   
  if resp.code != "200"
    printf(STDERR, "getResponse Parser Error: #%d from:%s\n", resp.code, url)
    raise JSON::ParserError    # this is a kludge, should raise a proper exception!!!!!
    return ""
  end

  result = JSON.parse(data)
  return result
end

if ARGV.length < 1
  puts "usage: #{$0} id"
  exit
end

id = ARGV[0].to_i

topic_url = "products/mozilla_thunderbird/topics/" << "%d" % id << ".json" 
printf(STDERR, "topic_url")
begin
  topic = getResponse(topic_url)
rescue JSON::ParserError
  printf(STDERR, "Parser error in topic:%s\n", topic_url)
  exit
end

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
topic["tags_array"] = [] 
topic["tag_id_array"] = []
topic["reply_id_array"] = [] 
topic["reply_array"] = []
topic["fulltext"] = "" 
topic["fulltext_with_tags"] = ""
topic["tags_str"] = "" 
topic["synthetic_status_journal"] = []

topic_text = topic["subject"].downcase + " " + topic["content"].downcase 
status = topic["status"]
status_update_time = last_active_at 
reply_count = topic["reply_count"] 
printf(STDERR, "reply_count:%d\n", reply_count) 
topic["reply_count"] = reply_count 
topic["fulltext"] = topic_text 
topic["fulltext_with_tags"] = topic_text
reply_page = 1
if reply_count != 0
  begin # while reply_count > 0
    get_reply_url = "topics/" + topic["slug"] + "/replies.json?sort=recently_created&page=" << "%d" % reply_page << "&limit=30"

    PP::pp(get_reply_url, $stderr)
    skip = false
    begin 
      replies = getResponse(get_reply_url)
    rescue JSON::ParserError
      printf(STDERR, "Parser error in reply:%s\n", get_reply_url)
      reply_count -= 30
      reply_page += 1
      skip = true
    end
    if skip
      skip = false 
      $stderr.printf("JSON error SKIPPING to next page of replies, reply_count:%d\n", reply_count)
      next
    end

    replies["data"].each do|reply|
      printf(STDERR, "START*** of reply\n")
      PP::pp(reply, $stderr)
      printf(STDERR, "\nEND*** of reply\n")
      author = reply["author"]["canonical_name"]
      reply_created_time = Time.parse(reply["created_at"])
      reply_created_time = reply_created_time.utc
      topic_id = reply["topic_id"]
      reply_id = reply["id"]
      printf(STDERR, "RRR: reply created time:%s\n", reply_created_time)
      reply.delete("created_at")
      reply["created_at"] = reply_created_time
      # always get all replies
      topic["fulltext"] = topic["fulltext"] + " " +  reply["content"].downcase
      topic["fulltext_with_tags"] = topic["fulltext"]
      topic["reply_id_array"].push(reply["id"])
      topic["reply_array"].push(reply)
    end # replies ... do
    reply_count -= 30
    reply_page += 1
  end while reply_count > 0
end # if reply_count != 0

tags_page = 1
tag_count = 1 # kludge
first_tag_page = true
while tag_count > 0         
  get_tags_url = "topics/" + topic["slug"] + "/tags.json?page=" << "%d" % tags_page << "&limit=30"
  PP::pp(get_tags_url, $stderr)
  skip = false
  begin 
    tags = getResponse(get_tags_url)
  rescue JSON::ParserError
    printf(STDERR, "Parser error in HTTP GET of tag url:%s\n", get_tags_url)
    tag_count -= 30
    tags_page += 1
    skip = true
  end
  if skip
    skip = false
    next
  end        
  if first_tag_page
    tag_count = tags["total"]
    topic["tag_count"] = tag_count
    first_tag_page = false
    $stderr.printf("TAG COUNT:%d\n",tag_count)
  end
  if tag_count > 0 
    tags["data"].each do|tag|    
      printf(STDERR, "START*** of tag\n")
      PP::pp(tag, $stderr)
      printf(STDERR, "\nEND*** of tag\n")
      tag_name = tag["name"].downcase
      if tag_name.length < 80
        topic["tags_array"].push(tag_name)
        topic["tag_id_array"].push({ "id" => tag["id"], "name" => tag_name})
        topic["tags_str"] = topic["tags_str"] + tag_name + "~"
        topic["fulltext_with_tags"] = topic["fulltext_with_tags"] + " " + tag_name
      else
        $stderr.printf("SKIPPING >80 character tag!!\n")
      end
    end # tags ... do
  end
  tag_count -= 30
  tags_page += 1                   
end # while tag_count > 0

ap topic, :indent => -2

