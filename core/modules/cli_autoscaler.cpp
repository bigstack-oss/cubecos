// HEX SDK

#include <hex/log.h>
#include <hex/strict.h>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

#define STORE_DIR "/var/response"

static int
CloudAutoScalerMain(int argc, const char** argv)
{
    if (argc > 12)
        return CLI_INVALID_ARGS;

    int index;
    int argidx = 1;
    std::string cmd, desc, media, dir;
    std::string tenant, user, vm, event, name, provider;
    std::string gcp_proj, gcp_zone, gcp_mtype, gcp_image, gcp_cred, gcp_userdata;

    cmd = HEX_SDK " os_list_project_by_domain_basic default";
    if (CliMatchCmdHelper(argc, argv, argidx++, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_instance_list " + tenant;
    if (CliMatchCmdHelper(argc, argv, argidx++, cmd, &index, &vm, "Select instance: ") != CLI_SUCCESS) {
        CliPrintf("Invalid instance name");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " alert_vm_event_list";
    desc = HEX_SDK " -v alert_vm_event_list";
    if (CliMatchCmdDescHelper(argc, argv, argidx++, cmd, desc, &index, &event, "Select event ID: ") != CLI_SUCCESS) {
        CliPrintf("Invalid event ID");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, argidx++, "Input rule name: ", &name) || name.length() <= 0) {
        CliPrint("Rule name is required");
        return CLI_INVALID_ARGS;
    }

    if (CliMatchCmdHelper(argc, argv, argidx++, "echo 'GCP'", &index, &provider, "Select cloud provider: ") != CLI_SUCCESS) {
        CliPrintf("Unknown cloud provider");
        return CLI_INVALID_ARGS;
    }

    if (provider == "GCP") {
        if (!CliReadInputStr(argc, argv, argidx++, "Input GCP project name: ", &gcp_proj) || gcp_proj.length() <= 0) {
            CliPrint("GCP project name is required");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " gcp_zone_list";
        if (CliMatchCmdHelper(argc, argv, argidx++, cmd, &index, &gcp_zone, "Select zone: ", 2) != CLI_SUCCESS) {
            CliPrintf("Invalid zone");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " gcp_machine_type_list " + gcp_zone;
        desc = HEX_SDK " -v gcp_machine_type_list " + gcp_zone;
        if (CliMatchCmdDescHelper(argc, argv, argidx++, cmd, desc, &index, &gcp_mtype, "Select machine type: ", 3) != CLI_SUCCESS) {
            CliPrintf("Invalid machine type");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " gcp_image_list";
        if (CliMatchCmdHelper(argc, argv, argidx++, cmd, &index, &gcp_image, "Select image: ", 2) != CLI_SUCCESS) {
            CliPrintf("Invalid image");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " gcp_credential_list " STORE_DIR;
        if (CliMatchCmdHelper(argc, argv, argidx++, cmd, &index, &gcp_cred, "Select GCP credential json file in " STORE_DIR ": ") != CLI_SUCCESS) {
            CliPrintf("no matched GCP credential file in " STORE_DIR);
            return CLI_INVALID_ARGS;
        }

        gcp_cred = STORE_DIR "/" + gcp_cred;

        cmd = HEX_SDK " gcp_userdata_list " STORE_DIR;
        CliMatchCmdHelper(argc, argv, argidx++, cmd, &index, &gcp_userdata, "Select compute engine user data in " STORE_DIR " (press enter to skip if none): ");

        if (gcp_userdata.length())
            gcp_userdata = STORE_DIR "/" + gcp_userdata;

        CliPrintf("\nGCP Auto Scaling Rule Summary:");
        CliPrintf("[Local]");
        CliPrintf("   Rule name: %s", name.c_str());
        CliPrintf("   Project: %s", tenant.c_str());
        CliPrintf("   VM name: %s", vm.c_str());
        CliPrintf("   Event ID: %s", event.c_str());

        CliPrintf("[GCP]");
        CliPrintf("   Project: %s", gcp_proj.c_str());
        CliPrintf("   Zone: %s", gcp_zone.c_str());
        CliPrintf("   Machine type: %s", gcp_mtype.c_str());
        CliPrintf("   Image: %s", gcp_image.c_str());
        CliPrintf("   Credential file: %s", gcp_cred.c_str());
        CliPrintf("   User data: %s", gcp_userdata.length() ? gcp_userdata.c_str() : "none");

        if (!CliReadConfirmation())
            return CLI_SUCCESS;

        CliPrint("Creating GCP auto scaling rule ...");
        if (HexSpawn(0, HEX_SDK, "gcp_auto_scaler_create",
            name.c_str(), gcp_proj.c_str(), gcp_zone.c_str(), gcp_mtype.c_str(), gcp_image.c_str(),
            event.c_str(), vm.c_str(), tenant.c_str(), gcp_cred.c_str(), gcp_userdata.c_str(), NULL) == 0) {
            CliPrint("GCP auto scaling rule created successfully");
        }
        else {
            CliPrint("Failed to create GCP auto scaling rule");
        }

    }

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "hybrid_cloud",
    "Work with hybrid cloud settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("hybrid_cloud", "cloud_autoscaler_create", CloudAutoScalerMain, NULL,
        "Create public cloud auto scaler rule (upload to /var/response).",
        "cloud_autoscaler_create <project> <instance> <event_id> <rule_name> <gcp>\n"
        "      gcp: <gcp_project> <zone> <machine-type> <image> <cloud-credential> <useradata>");

