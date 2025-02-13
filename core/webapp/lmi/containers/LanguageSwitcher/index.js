import React, { Component } from "react";
import { connect } from "react-redux";
import IntlMessages from "../../components/utility/intlMessages";
import actions from "../../redux/languageSwitcher/actions";
import config from "./config";

const { changeLanguage } = actions;

class LanguageSwitcher extends Component {
	render() {
		const { language, changeLanguage } = this.props;
		return (
			<div className="themeSwitchBlock">
				<h4>
					<IntlMessages id="languageSwitcher.label" />
				</h4>
				<div className="themeSwitchBtnWrapper">
					{config.options.map(option => {
						const { languageId, icon } = option;
						const customClass =
							languageId === language.languageId
								? "selectedTheme languageSwitch"
								: "languageSwitch";

						return (
							<button
								type="button"
								className={customClass}
								key={languageId}
								onClick={() => {
									changeLanguage(languageId);
								}}
							>
								<img src={icon} alt="flag" />
							</button>
						);
					})}
				</div>
			</div>
		);
	}
}

export default connect(
	state => ({
		...state.LanguageSwitcher
	}),
	{ changeLanguage }
)(LanguageSwitcher);
