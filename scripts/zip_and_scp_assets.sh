SNARKVM_DIR=snarkVM
ALEO_PROGRAM_REGRESSIONS_DIR=aleo-program-regressions
MACHINE_IP=35.90.138.224

cd ${SNARKVM_DIR} && cargo clean && cd -
zip -vr snarkvm.zip ${SNARKVM_DIR} -x '*.git*'
zip -vr aleo-program-regressions.zip ${ALEO_PROGRAM_REGRESSIONS_DIR} -x '*target*' -x '*.git*'
scp aleo-program-regressions.zip ubuntu@${MACHINE_IP}:
scp snarkvm.zip ubuntu@${MACHINE_IP}:
ssh ubuntu@${MACHINE_IP} unzip snarkvm.zip
ssh ubuntu@${MACHINE_IP} unzip aleo-program-regressions.zip

