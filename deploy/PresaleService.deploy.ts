import { HardhatRuntimeEnvironment } from "hardhat/types";

module.exports = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { admin } = await getNamedAccounts();

  const uniswapMock = await deployments.get("UniswapMock");

  await deploy("PresaleService", {
    from: admin,
    args: [uniswapMock.address, 500], // 5% usage fees = 500bps
    log: true,
    deterministicDeployment: false,
  });
};
module.exports.tags = ["PresaleService"];
module.exports.dependencies = ["UniswapMock"];
