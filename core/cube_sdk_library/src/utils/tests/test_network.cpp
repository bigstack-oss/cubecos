// CUBE SDK

#include <string.h>
#include <unistd.h>

#include <hex/test.h>
#include <cube/network.h>

int main()
{
  std::string pIf = GetParentIf("eth0");
  printf("eth0 pIf = %s\n", pIf.c_str());
  HEX_TEST(pIf == "br0");

  pIf = GetParentIf("eth1");
  printf("eth1 pIf = %s\n", pIf.c_str());
  HEX_TEST(GetParentIf("eth1") == "br0");

  pIf = GetParentIf("eth2");
  printf("eth2 pIf = %s\n", pIf.c_str());
  HEX_TEST(GetParentIf("eth2") == "br0");

  pIf = GetParentIf("eth3");
  printf("eth3 pIf = %s\n", pIf.c_str());
  HEX_TEST(GetParentIf("eth3") == "eth3");

  pIf = GetParentIf("eth4");
  printf("eth4 pIf = %s\n", pIf.c_str());
  HEX_TEST(GetParentIf("eth4") == "eth4");

  pIf = GetParentIf("eth3.99");
  printf("eth3.99 pIf = %s\n", pIf.c_str());
  HEX_TEST(GetParentIf("eth3.99") == "eth3.99");

  return HexTestResult;
}
