<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('password','password-confirm'); section>
    <#if section = "header">
        ${msg("updatePasswordTitle")}
    <#elseif section = "form">
    <div class="form-container p-12 bg-blue-100">
        <div class="form__header flex flex-col items-center mb-4">
            <img src="${url.resourcesPath}/img/${properties.imageName}" alt="cmp-login-logo" style="${properties.customImgStyle}">
            <p class="text-white-70 font-semibold text text-lg mt-4">Update Password</p>
        </div>
        <div id="passwd-update-form-wrapper" class="form__login-form-wrapper w-full flex flex-col">
            <form id="kc-passwd-update-form" class="${properties.kcFormClass!} w-full flex flex-col" action="${url.loginAction}" method="post">
                <div class="form__row flex flex-col mb-2 relative pb-6">
                    <label for="password-new" class="text-white-100 text-sm mb-2">${msg("passwordNew")}</label>
                    <input 
                        tabindex="1" 
                        type="password" 
                        id="password-new" 
                        name="password-new" 
                        class="form__input bg-blue-80 text-white-100 placeholder:text-white-30 placeholder:text-sm h-[40px] px-4 transition-all"
                        autofocus 
                        autocomplete="new-password"
                        aria-invalid="<#if messagesPerField.existsError('password','password-confirm')>true</#if>"
                    />
                    <#if messagesPerField.existsError('password')>
                        <span id="input-error-password" class="form__field-error text-xs text-red-400 absolute bottom-0" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('password'))?no_esc}
                        </span>
                    </#if>
                </div>
                <div class="form__row flex flex-col mb-2 relative pb-6">
                    <label for="password-confirm" class="text-white-100 text-sm mb-2">${msg("passwordConfirm")}</label>
                    <input 
                        type="password" 
                        id="password-confirm" 
                        name="password-confirm"
                        class="form__input bg-blue-80 text-white-100 placeholder:text-white-30 placeholder:text-sm h-[40px] px-4 transition-all"
                        autocomplete="new-password"
                        aria-invalid="<#if messagesPerField.existsError('password-confirm')>true</#if>"
                    />
                    <#if messagesPerField.existsError('password-confirm')>
                        <span id="input-error-password-confirm" class="form__field-error text-xs text-red-400 absolute bottom-0" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('password-confirm'))?no_esc}
                        </span>
                    </#if>
                </div>
                <div id="kc-form-buttons">
                    <#if isAppInitiatedAction??>
                        <input class="form__submit w-1/2 h-[40px] bg-blue-50 transition-all hover:bg-blue-60 active:bg-blue-60 text-white-100 mt-4" type="submit" value="${msg("doSubmit")}" />
                        <button class="form__submit w-1/2 h-[40px] bg-blue-50 transition-all hover:bg-blue-60 active:bg-blue-60 text-white-100 mt-4" type="submit" name="cancel-aia" value="true" />${msg("doCancel")}</button>
                    <#else>
                        <input class="form__submit w-full h-[40px] bg-blue-50 transition-all hover:bg-blue-60 active:bg-blue-60 text-white-100 mt-4" type="submit" value="${msg("doSubmit")}" />
                    </#if>
                </div>
            </form>
        </div>   
    </div>
    </#if>
</@layout.registrationLayout>