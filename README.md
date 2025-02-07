SB AB Testing Kong plugin 
====================

Inspired by https://github.com/Kong/kong-plugin

For a complete walkthrough check [this blogpost on the Kong website](https://konghq.com/blog/custom-lua-plugin-kong-gateway).

### Configuration

```
{
  "id": "2e0485fe-2614-42e6-917a-3304dd4d14a7",
  "route": null,
  "service": {
    "id": "2c10e51c-1ad3-4b85-87df-4049a8d94b99"
  },
  "instance_name": "kh-webshop-ab-test",
  "protocols": [
    "http",
    "https"
  ],
  "tags": [],
  "updated_at": 1726769726,
  "created_at": 1726769726,
  "enabled": true,
  "name": "sb-ab-testing",
  "config": {
    "experiment": {
      "datetime_end": 1756810800,
      "uuid": "ceea82d6-bdda-430b-8c28-86aefa40fbc5",
      "groups": [
        {
          "site_name": "kh-webshop",
          "group_name": "66c7142d66f08d8defde50cd"
        },
        {
          "site_name": "kh-webshop-b",
          "group_name": "66e33964d38b37a1c21edda8"
        }
      ],
      "datetime_start": 1726170034
    },
    "log": true,
    "ab_splitter_api": {
      "base_url": "ab-splitter.xsolla.com",
      "path": "/v3/split/by_experiment_uuid",
      "timeout": 10000
    }
  },
  "consumer": null
}
```

### Deploy
1. Make changes to the code
2. Update version in file `kong-plugin-sb-ab-testing-{version}-{revision}` and change file name
2. Push it to master
3. Create tag by version `git tag 0.3.3-0 -m "<tag message>"`
4. Push tag `git push origin 0.3.3-0`
5. Create pack `luarocks pack kong-plugin-sb-ab-testing-0.3.3-0.rockspec`
6. Upload pack `luarocks upload kong-plugin-sb-ab-testing-0.3.3-0.rockspec --api-key=`. Get API key from keeper