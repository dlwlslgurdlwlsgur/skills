function add_timestamp(tag, timestamp, record)
    record["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(timestamp))
    return 1, timestamp, record
end
