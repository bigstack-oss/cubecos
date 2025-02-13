// CUBE SDK

#include <string.h>
#include <unistd.h>

#include <hex/test.h>
#include <cube/config_file.h>

#define TESTFILE "test.dat"

int main()
{
    FILE *f;
    Configs configs;

    // CASE1: only global settings
    HEX_TEST_FATAL((f = fopen(TESTFILE, "w")) != NULL);
    fprintf(f, "name0=value0\n");
    fprintf(f, "name1=value1\n");
    fprintf(f, "name2=value2\n");
    fclose(f);

    HEX_TEST_FATAL(LoadConfig(TESTFILE, SB_SEC_RFMT, '=', configs));
    HEX_TEST(configs[GLOBAL_SEC]["name0"] == "value0");
    HEX_TEST(configs[GLOBAL_SEC]["name1"] == "value1");
    HEX_TEST(configs[GLOBAL_SEC]["name2"] == "value2");

    unlink(TESTFILE);
    configs.clear();

    // CASE2: only sec settings
    HEX_TEST_FATAL((f = fopen(TESTFILE, "w")) != NULL);
    fprintf(f, "[section0]\n");
    fprintf(f, "name0=value0\n");
    fprintf(f, "name1=value1\n");
    fprintf(f, "name2=value2\n");
    fclose(f);

    HEX_TEST_FATAL(LoadConfig(TESTFILE, SB_SEC_RFMT, '=', configs));
    HEX_TEST(configs["section0"]["name0"] == "value0");
    HEX_TEST(configs["section0"]["name1"] == "value1");
    HEX_TEST(configs["section0"]["name2"] == "value2");

    unlink(TESTFILE);
    configs.clear();

    // CASE3: global + section setting
    HEX_TEST_FATAL((f = fopen(TESTFILE, "w")) != NULL);
    fprintf(f, "name0=value0\n");
    fprintf(f, "name1=value1\n");
    fprintf(f, "name2=value2\n");
    fprintf(f, "[section0]\n");
    fprintf(f, "name3   =value3\n");                                    // trailing spaces after name
    fprintf(f, "name4=   value4\n");                                    // leading spaces before value
    fclose(f);

    HEX_TEST_FATAL(LoadConfig(TESTFILE, SB_SEC_RFMT, '=', configs));
    HEX_TEST(configs[GLOBAL_SEC]["name0"] == "value0");
    HEX_TEST(configs[GLOBAL_SEC]["name1"] == "value1");
    HEX_TEST(configs[GLOBAL_SEC]["name2"] == "value2");
    HEX_TEST(configs["section0"]["name3"] == "value3");
    HEX_TEST(configs["section0"]["name4"] == "value4");

    unlink(TESTFILE);
    configs.clear();

    // CASE3: only section setting
    HEX_TEST_FATAL((f = fopen(TESTFILE, "w")) != NULL);
    fprintf(f, "  [section0]\n");
    fprintf(f, "\t[section1]\n");
    fprintf(f, "[section2]\n");
    fprintf(f, "[section3]\n");
    fprintf(f, "[[section4]]\n");
    fprintf(f, "[[[section5]]]\n");
    fclose(f);

    HEX_TEST_FATAL(LoadConfig(TESTFILE, SB_SEC_RFMT, '=', configs));
    HEX_TEST(configs[GLOBAL_SEC].size() == 0);
    HEX_TEST(configs["section0"].size() == 0);
    HEX_TEST(configs["section1"].size() == 0);
    HEX_TEST(configs["section2"].size() == 0);
    HEX_TEST(configs["section3"].size() == 0);
    HEX_TEST(configs.find("[section4]") != configs.end());
    HEX_TEST(configs.find("[[section5]]") != configs.end());

    unlink(TESTFILE);
    configs.clear();

    // CASE5: integration test
    HEX_TEST_FATAL((f = fopen(TESTFILE, "w")) != NULL);
    fprintf(f, "name0=value0\n");
    fprintf(f, "   name1=value1\n");
    fprintf(f, "[section0]\n");
    fprintf(f, "name2   =value2\n");                                    // trailing spaces after name
    fprintf(f, "name3=   value3\n");                                    // leading spaces before value
    fprintf(f, "name4=value4   \n");                                    // leading spaces before value
    fprintf(f, "\t[section1]\n");                                       // leading tabs before section
    fprintf(f, "name5  =  value5\n");                                   // space after name and before value
    fprintf(f, "name6\t=value6\n");                                     // trailing tabs after name
    fprintf(f, "name7=\tvalue7\n");                                     // leading tabs before value
    fprintf(f, "name8=value8\t\n");                                     // leading tabs before value
    fprintf(f, "name9=value9 value9   value9\n");                       // spaces inside value
    fprintf(f, " \t name10 \t = \t value10 value10   value10 \t \n");   // all of the above
    fprintf(f, "\t[section2]\n");
    fclose(f);

    HEX_TEST_FATAL(LoadConfig(TESTFILE, SB_SEC_RFMT, '=', configs));
    HEX_TEST(configs[GLOBAL_SEC]["name0"] == "value0");
    HEX_TEST(configs[GLOBAL_SEC]["name1"] == "value1");
    HEX_TEST(configs["section0"]["name2"] == "value2");
    HEX_TEST(configs["section0"]["name3"] == "value3");
    HEX_TEST(configs["section0"]["name4"] == "value4");
    HEX_TEST(configs["section1"]["name5"] == "value5");
    HEX_TEST(configs["section1"]["name6"] == "value6");
    HEX_TEST(configs["section1"]["name7"] == "value7");
    HEX_TEST(configs["section1"]["name8"] == "value8");
    HEX_TEST(configs["section1"]["name9"] == "value9 value9   value9");
    HEX_TEST(configs["section1"]["name10"] == "value10 value10   value10");

    // for debugging
    DumpConfig("[%s]", '=', configs);

    unlink(TESTFILE);

    // write config and verify
    HEX_TEST_FATAL(WriteConfig(TESTFILE, "[%s]", '=', configs));
    configs.clear();

    HEX_TEST_FATAL(LoadConfig(TESTFILE, SB_SEC_RFMT, '=', configs));
    HEX_TEST(configs[GLOBAL_SEC]["name0"] == "value0");
    HEX_TEST(configs[GLOBAL_SEC]["name1"] == "value1");
    HEX_TEST(configs["section0"]["name2"] == "value2");
    HEX_TEST(configs["section0"]["name3"] == "value3");
    HEX_TEST(configs["section0"]["name4"] == "value4");
    HEX_TEST(configs["section1"]["name5"] == "value5");
    HEX_TEST(configs["section1"]["name6"] == "value6");
    HEX_TEST(configs["section1"]["name7"] == "value7");
    HEX_TEST(configs["section1"]["name8"] == "value8");
    HEX_TEST(configs["section1"]["name9"] == "value9 value9   value9");
    HEX_TEST(configs["section1"]["name10"] == "value10 value10   value10");

    unlink(TESTFILE);
    configs.clear();

    return HexTestResult;
}

