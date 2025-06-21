<!--
  Copyright (C) 2022 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("packages.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getPackages">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getPackages"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <h1>Packages</h1>
            {{ packages }}
            <cv-grid>
              <cv-row>
                <cv-column :sm="4" :lg="6">
                  <cv-tile
                    kind="clickable"
                    @click.prevent="onRemovePackage(pkg)"
                    v-for="(version, pkg) in packages"
                    :key="pkg"
                  >
                    {{ pkg }}: {{ version }}<br />
                    Zum Entfernen klicken
                  </cv-tile>
                </cv-column>
              </cv-row>
            </cv-grid>
            <cv-grid :full-width="true" :kind="'wide'">
              <cv-row>
                <cv-column>
                  <cv-text-input
                    label="Package"
                    placeholder="typo3/cms-core"
                    v-model.trim="pkgName"
                    class="mg-bottom"
                    :invalid-message="$t(error.pkgName)"
                    :disabled="loading.getPackages || loading.configureModule"
                    ref="pkgName"
                  >
                  </cv-text-input>
                </cv-column>
                <cv-column>
                  <cv-text-input
                    label="Version"
                    placeholder="^13.4"
                    v-model.trim="pkgVersion"
                    class="mg-bottom"
                    :invalid-message="$t(error.pkgVersion)"
                    :disabled="loading.getPackages || loading.configureModule"
                    ref="pkgVersion"
                  >
                  </cv-text-input>
                </cv-column>
              </cv-row>
            </cv-grid>
            <CvButton
              type="button"
              :icon="Add20"
              :loading="loading.configureModule"
              :disabled="loading.getPackages || loading.configureModule"
              @click.prevent="onAddPackage"
              >{{ $t("packages.add") }}
            </CvButton>
            <cv-row v-if="error.configureModule">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.configure-module')"
                  :description="error.configureModule"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="loading.getPackages || loading.configureModule"
              >{{ $t("packages.save") }}
            </NsButton>
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

export default {
  name: "Packages",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("packages.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "packages",
      },
      urlCheckInterval: null,
      packages: {},
      pkgName: "",
      pkgVersion: "",
      loading: {
        getPackages: false,
        configureModule: false,
      },
      error: {
        getPackages: "",
        configureModule: "",
        packages: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
  },
  created() {
    this.getPackages();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    onRemovePackage(pkgName) {
      console.log("huhu", pkgName, this.packages);
      delete this.packages[pkgName];
      console.log(this.packages);
    },
    async onAddPackage() {
      this.packages[this.pkgName] = this.pkgVersion;

      this.error.test_imap = false;
      this.error.test_smtp = false;
      const isValidationOk = this.validateConfigureModule();
      if (!isValidationOk) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "add-composer-package";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );

      // register to task validation
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            packageName: this.pkgName,
            packageVersion: this.pkgVersion,
          },
          extra: {
            title: this.$t("packages.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("packages.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
      }

      this.pkgName = "";
      this.pkgVersion = "";
    },
    async getPackages() {
      this.loading.getPackages = true;
      this.error.getPackages = "";
      const taskAction = "get-composer-packages";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getPackagesAborted
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getPackagesCompleted
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getPackages = this.getErrorMessage(err);
        this.loading.getPackages = false;
      }
    },
    getPackagesAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getPackages = this.$t("error.generic_error");
      this.loading.getPackages = false;
    },
    getPackagesCompleted(taskContext, taskResult) {
      this.packages = taskResult.output.packages;

      this.loading.getPackages = false;
      this.focusElement("pkgName");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      return true;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;

      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        // set i18n error message
        this.error[param] = this.$t("packages." + validationError.error);

        if (!focusAlreadySet) {
          this.focusElement(param);
          focusAlreadySet = true;
        }
      }
    },
    async configureModule() {
      this.error.test_imap = false;
      this.error.test_smtp = false;
      const isValidationOk = this.validateConfigureModule();
      if (!isValidationOk) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "add-composer-package";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );

      // register to task validation
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            packages: this.packages,
          },
          extra: {
            title: this.$t("packages.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("packages.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;

      // reload configuration
      this.getPackages();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";

.mg-bottom {
  margin-bottom: $spacing-06;
}

.maxwidth {
  max-width: 38rem;
}
</style>
