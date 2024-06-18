# Using Pre-built Binaries

To speed up testing, you can use pre-built binaries for snarkOS and tx-cannon.

There are two ways to build the binaries:
### **Use pre-built mainnet binaries** 
Recommended when the test only requires the latest mainnet branch.
### **Build binaries yourself on github** 
Recommend when the test requires a custom build of SnarkOS or tx-cannon.


## OPTION 1: Use pre-built mainnet binaries
If you are creating a new test, you can copy the `hello_hello` test suite as a
starting template for your test as both of these tests use pre-built binaries
and will not require you to make any further test modifications to use the
pre-built binaries.

### Prebuilt SnarkOS Binaries
The SnarkOS binaries are built using `github actions` on the
`ProvableHQ/snarkOS-staging` repository.

The binaries can be installed by adding the following ansible steps to the
`snarkos_setup.yml` file in the `Setup snarkOS nodes` task. This assumes your
`gh_token` is set and `gh` installed.

```yml
    - name: Download snarkOS binary with GitHub CLI 
      shell: >
        TAG=mainnet-latest

        apt-get install -y unzip

        GITHUB_TOKEN="{{ gh_token }}" gh release download ${TAG}
        --repo ProvableHQ/snarkOS-staging
        --pattern "snarkos*unknown-linux-gnu.zip"
        --output "/usr/bin/snarkos.zip"
        --skip-existing

        unzip -o /usr/bin/snarkos.zip -d /usr/bin
      environment:
        GITHUB_TOKEN: "{{ gh_token }}"
      args:
        executable: /bin/bash
      become: yes

    - name: Make snarkos executable
      file:
        path: "/usr/bin/snarkos"
        mode: '0755'
```

These binaries are maintained to the latest mainnet changes so no further action is required.

### Prebuilt Tx-Cannon Binaries
The tx-cannon binaries are also built using `github actions` in
`ProvableHQ/tx-cannon` repository.

The tx-cannon binaries can be installed by adding the following ansible steps to
the `snarkos_setup.yml` file in the `Set up and run tx-cannon` ansible task.
This assumes your `gh_token` is set and `gh` installed.

```yaml
    - name: Download tx-cannon binary with GitHub CLI 
      shell: >
        TAG=mainnet-latest

        apt-get install -y unzip

        GITHUB_TOKEN="{{ gh_token }}" gh release download ${TAG}
        --repo ProvableHQ/tx-cannon
        --pattern "tx-cannon*unknown-linux-gnu.zip"
        --output "/usr/bin/tx-cannon.zip"
        --skip-existing

        unzip -o /usr/bin/tx-cannon.zip -d /usr/bin
      environment:
        GITHUB_TOKEN: "{{ gh_token }}"
      args:
        executable: /bin/bash
      become: yes
  
    - name: Make tx-cannon executable
      file:
        path: "/usr/bin/tx-cannon"
        mode: '0755'
```

## OPTION 2: Build binaries yourself on github
If you need to build the binaries yourself, you can use the following steps to build the binaries on github:

### Custom SnarkOS Binaries

The steps:
1. **Make a branch with your desired changes in the [snarkOS-staging](https://github.com/ProvableHQ/snarkOS-staging)** branch
2. **On the commit you want to build a binary from run:**
```bash
git tag <your tag> && git push origin <your tag>
```
This will trigger a build on the `snarkOS-staging` branch
3. **Add the ansible code in the [snarkos binaries](#prebuilt-snarkos-binaries) section above with appropriate #{TAG_VERSION} to your test**

### Custom Tx-Cannon Binaries
Follow the steps below to build the tx-cannon binaries on github.

The steps:
1. **Make a branch with your desired changes in the [tx-cannon repo](https://github.com/ProvableHQ/tx-cannon)**
2. **On the commit you want to build a binary from run:**
```bash
git tag <your tag> && git push origin <your tag>
```
This will trigger a build on the `tx-cannon` branch under the name of your tag
3. **Add the ansible code in the [tx-cannon binaries](#prebuilt-tx-cannon-binaries) section above with appropriate #{TAG_VERSION} to your test**
