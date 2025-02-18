<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=realm.password && realm.registrationAllowed && !registrationDisabled??; section>
        <!-- FORM BEGIN -->
        <div class="form-container p-12 bg-blue-100">
            <!-- HEADER BEGIN -->
            <div class="form__header flex flex-col items-center mb-4">
                <img src="${url.resourcesPath}/img/${properties.imageName}" alt="cmp-login-logo" style="${properties.customImgStyle}">
                <#if properties.loginGreeting != "">
                    <p class="text-white-70 font-semibold text text-lg mt-4">${properties.loginGreeting}</p>
                </#if>
            </div>
            <!-- HEADER END -->
            <!-- PASSWORD SIGNIN START -->
            <#if realm.password>
            <div id="login-form-wrapper" class="form__login-form-wrapper w-full flex flex-col">
                <!-- PROVIDER SIGNIN START -->
                <#if realm.password && social.providers??>
                    <div id="kc-social-providers" style="text-align:center;">
                        <ul class="${properties.kcFormSocialAccountListClass!} <#if social.providers?size gt 3>${properties.kcFormSocialAccountListGridClass!}</#if>">
                            <#list social.providers as p>
                                <a id="social-${p.alias}" href="${p.loginUrl}">
                                    <button class="form__sso-btn bg-white-100 text-blue-100 flex w-full h-[40px] items-center justify-center font-semibold text-sm hover:bg-white-70 focus:bg-white-70 transition-all" style="margin-bottom: 8px">
                                    Login with ${p.displayName!}
                                    </button>
                                </a>
                            </#list>
                        </ul>
                    </div>
                    <div id="kc-form-separator" style="display:flex" class="form__separator w-full flex justify-center items-center mt-4 mb-8 relative">
                        <span class="text-white-70 flex h-full bg-blue-100 px-6 z-10 text-sm">OR</span>
                    </div>
                    <#if !messagesPerField.existsError('username','password')>
                        <div id="kc-other-method-desc" class="form__first_desc w-full flex justify-center items-center mb-4 relative" onclick="showOtherLoginMethods()">
                            <span class="flex h-full bg-blue-100 px-6 z-10 text-sm">Try a different way to login ?</span>
                        </div>
                    </#if>  
                </#if>
                <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post" class="form text-white-100" style="display:<#if !messagesPerField.existsError('username','password') && realm.password && social.providers??>none<#else>block</#if>">
                    <div class="form__row flex flex-col mb-2 relative pb-6">
                        <label for="username" class="text-white-100 text-sm mb-2">${msg("username")}</label>
                        <input tabindex="1" id="username" class="form__input bg-blue-80 text-white-100 placeholder:text-white-30 placeholder:text-sm h-[40px] px-4 transition-all" name="username" value="${(login.username!'')}"  type="text" autofocus autocomplete="off"
                            aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>"
                        />
                        <#if messagesPerField.existsError('username','password')>
                            <span data-field="username" id="input-error" class="form__field-error text-xs text-red-400 absolute bottom-0" aria-live="polite">
                                ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
                            </span>
                        </#if>
                    </div>

                    <div class="form__row flex flex-col mb-2 relative pb-6">
                        <label for="password" class="text-white-100 text-sm mb-2">${msg("password")}</label>
                        <input tabindex="2" id="password" class="form__input bg-blue-80 text-white-100 placeholder:text-white-30 placeholder:text-sm h-[40px] px-4 transition-all" name="password" type="password" autocomplete="off"
                            aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>"
                        />
                    </div>
                    <div id="kc-form-buttons" class="${properties.kcFormGroupClass!}">
                        <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>
                        <button id="submit-login" class="form__submit w-full h-[40px] bg-blue-50 transition-all hover:bg-blue-60 active:bg-blue-60 text-white-100 mt-4" type="submit">
                            ${msg("doLogIn")}
                        </button>
                    </div>
                </form>
            </div>
            </#if>
        </div>
</@layout.registrationLayout>
