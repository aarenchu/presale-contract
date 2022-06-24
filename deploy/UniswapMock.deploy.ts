import { HardhatRuntimeEnvironment } from "hardhat/types";

module.exports = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { admin } = await getNamedAccounts();

  const mlp = await deployments.get("MLPToken");

  await deploy("UniswapMock", {
    from: admin,
    args: [mlp.address],
    log: true,
    deterministicDeployment: false,
  });
};
module.exports.tags = ["UniswapMock"];
module.exports.dependencies = ["MLPToken"];
