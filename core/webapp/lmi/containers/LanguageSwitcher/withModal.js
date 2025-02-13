import React, { Component } from "react";
import { connect } from "react-redux";
import Modal from "../../components/feedback/modal";
import Button from "../../components/uielements/button";
import actions from "../../redux/languageSwitcher/actions";
import config from "./config";

const { switchActivation, changeLanguage } = actions;

class LanguageSwitcher extends Component {
	render() {
		const {
			isActivated,
			language,
			switchActivation,
			changeLanguage
		} = this.props;
		return (
			<div className="isoButtonWrapper">
				<Button type="primary" className="" onClick={switchActivation}>
					Switch Language
				</Button>

				<Modal
					title={"Select Language"}
					visible={isActivated}
					onCancel={switchActivation}
					cancelText="Cancel"
					footer={[]}
				>
					<div>
						{config.options.map(option => {
							const { languageId, text } = option;
							const type =
								languageId === language.languageId ? "primary" : "success";
							return (
								<Button
									type={type}
									key={languageId}
									onClick={() => {
										changeLanguage(languageId);
									}}
								>
									{text}
								</Button>
							);
						})}
					</div>
				</Modal>
			</div>
		);
	}
}

export default connect(
	state => ({
		...state.LanguageSwitcher
	}),
	{ switchActivation, changeLanguage }
)(LanguageSwitcher);
