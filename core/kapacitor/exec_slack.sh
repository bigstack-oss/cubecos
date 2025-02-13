#!/bin/bash

# send to slack channnel
# the script is running inside an alpine linux pod

# read alert data from stdin
# e.g.
# {
#   "name": "system",
#   "tags": {
#     "category": "SYS",
#     "key": "SYS00001I",
#     "severity": "I",
#     "test": "test"
#   },
#   "columns": [
#     "time",
#     "message",
#     "metadata"
#   ],
#   "values": [
#     [
#       "2021-05-30T10:40:34Z",
#       "system info alert",
#       "{\"test\":\"test\"}"
#     ]
#   ]
# }
DATA=$(cat)

# print 'system info alert' in slack channel
TOKEN=https://hooks.slack.com/services/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
curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"\`\`\`$(echo $DATA | jq -r .values[0][1])\`\`\`\"}" $TOKEN
