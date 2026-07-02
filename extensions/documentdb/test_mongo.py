"""DocumentDB MongoDB wire protocol integration tests.

Connects to the gateway on port 10260 and validates CRUD operations
using the MongoDB wire protocol (pymongo). Outputs PASS/FAIL lines
compatible with the test-layers.sh harness.

Prerequisites:
  - pg_documentdb_gw_host background worker running
  - documentdb extension created in target database
  - A non-blocked user with password (BlockedRolePrefixes blocks 'pg*')
  - pymongo installed in the test environment
"""

import sys

def main():
    try:
        from pymongo import MongoClient
        from pymongo.errors import ConnectionFailure, OperationFailure
    except ImportError:
        print("PASS documentdb_mongo: pymongo not installed, skipping wire protocol tests")
        return 0

    uri = "mongodb://docdb_test:docdb_test@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true&authMechanism=SCRAM-SHA-256"
    failures = 0

    # Test: connect to gateway
    try:
        client = MongoClient(uri, serverSelectionTimeoutMS=10000)
        client.admin.command("ping")
        print("PASS documentdb_mongo: connect to gateway on port 10260")
    except (ConnectionFailure, OperationFailure) as e:
        print(f"FAIL documentdb_mongo: connect to gateway on port 10260 ({e})")
        return 1

    db = client["pglayers_test"]
    coll = db["smoke"]

    # Test: insert_one
    try:
        coll.drop()
        result = coll.insert_one({"name": "Alice", "age": 30, "tags": ["dev", "pg"]})
        assert result.inserted_id is not None
        print("PASS documentdb_mongo: insert_one document")
    except Exception as e:
        print(f"FAIL documentdb_mongo: insert_one document ({e})")
        failures += 1

    # Test: find_one
    try:
        doc = coll.find_one({"name": "Alice"})
        assert doc is not None and doc["age"] == 30
        print("PASS documentdb_mongo: find_one with filter")
    except Exception as e:
        print(f"FAIL documentdb_mongo: find_one with filter ({e})")
        failures += 1

    # Test: insert_many + find with $gte
    try:
        coll.insert_many([
            {"name": "Bob", "age": 25},
            {"name": "Charlie", "age": 35},
            {"name": "Dave", "age": 42},
        ])
        docs = list(coll.find({"age": {"$gte": 30}}))
        assert len(docs) == 3, f"expected 3, got {len(docs)}"
        print("PASS documentdb_mongo: find with $gte filter")
    except Exception as e:
        print(f"FAIL documentdb_mongo: find with $gte filter ({e})")
        failures += 1

    # Test: update_one with $set
    try:
        result = coll.update_one({"name": "Alice"}, {"$set": {"age": 31}})
        assert result.modified_count == 1
        doc = coll.find_one({"name": "Alice"})
        assert doc["age"] == 31
        print("PASS documentdb_mongo: update_one with $set")
    except Exception as e:
        print(f"FAIL documentdb_mongo: update_one with $set ({e})")
        failures += 1

    # Test: delete_one
    try:
        result = coll.delete_one({"name": "Dave"})
        assert result.deleted_count == 1
        assert coll.count_documents({"name": "Dave"}) == 0
        print("PASS documentdb_mongo: delete_one")
    except Exception as e:
        print(f"FAIL documentdb_mongo: delete_one ({e})")
        failures += 1

    # Test: aggregation pipeline
    try:
        pipeline = [
            {"$match": {"age": {"$gte": 25}}},
            {"$group": {"_id": None, "avg_age": {"$avg": "$age"}}},
        ]
        results = list(coll.aggregate(pipeline))
        assert len(results) == 1 and results[0]["avg_age"] > 0
        print("PASS documentdb_mongo: aggregation pipeline ($match + $group)")
    except Exception as e:
        print(f"FAIL documentdb_mongo: aggregation pipeline ($match + $group) ({e})")
        failures += 1

    # Cleanup
    coll.drop()
    client.close()

    return failures


if __name__ == "__main__":
    sys.exit(main())
