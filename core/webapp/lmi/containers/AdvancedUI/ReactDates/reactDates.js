import React, { Component } from "react";
import { connect } from "react-redux";
import { Row, Col } from "antd";
import Tabs, { TabPane } from "../../../components/uielements/tabs";
import Switch from "../../../components/uielements/switch";
import Form from "../../../components/uielements/form";
import PageHeader from "../../../components/utility/pageHeader";
import Box from "../../../components/utility/box";
import LayoutWrapper from "../../../components/utility/layoutWrapper";
import ContentHolder from "../../../components/utility/contentHolder";
import ReactDatesCss from "react-dates/lib/css/_datepicker.css";
import {
	DateRangePicker,
	SingleDatePicker
} from "../../../components/uielements/reactDates";
import basicStyle from "../../../config/basicStyle";
import configs from "./config";
import { ReactDatesStyleWrapper, ReactDatesWrapper } from "./reactDates.style";

const FormItem = Form.Item;
class ReactDates extends Component {
	constructor(props) {
		super(props);
		this.renderDatePicker = this.renderDatePicker.bind(this);
		this.toggleOptions = this.toggleOptions.bind(this);
		this.state = {
			isRangePicker: false,
			configsValue: configs,
			singleFocused: true,
			singleResult: null,
			focusedInput: "startDate",
			startDate: null,
			endDate: null
		};
	}
	toggleOptions() {
		const { isRangePicker, configsValue } = this.state;
		const options =
			isRangePicker === true
				? configsValue[1].options
				: configsValue[0].options;
		return options.map((option, index) => {
			if (this.props.view === "MobileView" && option.id === "numberOfMonths") {
				return "";
			}
			const checked = option.value === option.trueValue;
			const onChange = () => {
				if (isRangePicker) {
					configsValue[1].options[index].value = checked
						? option.falseValue
						: option.trueValue;
				} else {
					configsValue[0].options[index].value = checked
						? option.falseValue
						: option.trueValue;
				}
				this.setState(configsValue);
			};
			return (
				<FormItem label={option.title} key={option.id}>
					<Switch checked={checked} onChange={onChange} />
				</FormItem>
			);
		});
	}
	renderDatePicker(config) {
		const {
			isRangePicker,
			startDate,
			endDate,
			focusedInput,
			singleResult,
			singleFocused,
			configsValue
		} = this.state;
		let options;
		if (isRangePicker) {
			options = {
				startDate,
				endDate,
				onDatesChange: ({ startDate, endDate }) =>
					this.setState({ startDate, endDate }),
				focusedInput,
				onFocusChange: focusedInput => {
					this.setState({ focusedInput });
				}
			};
		} else {
			options = {
				date: singleResult,
				onDateChange: singleResult => this.setState({ singleResult }),
				focused: singleFocused,
				onFocusChange: ({ focused }) =>
					this.setState({ singleFocused: focused })
			};
		}
		const renderOptions = isRangePicker
			? configsValue[1].options
			: configsValue[0].options;
		renderOptions.forEach(option => {
			options[option.id] = option.value;
		});
		if (this.props.view === "MobileView") {
			options.numberOfMonths = 1;
		}
		return (
			<div className="isoReactDate">
				{!isRangePicker ? (
					<SingleDatePicker {...options} />
				) : (
					<DateRangePicker isOutsideRange={() => false} {...options} />
				)}
			</div>
		);
	}
	render() {
		const { rowStyle, colStyle, gutter } = basicStyle;
		return (
			<div>
				<style>{ReactDatesCss}</style>
				<LayoutWrapper>
					<PageHeader>React Dates</PageHeader>
					<Row style={rowStyle} gutter={gutter} justify="start">
						<Col md={24} sm={24} xs={24} style={colStyle}>
							<Box>
								<ContentHolder>
									<Tabs
										onChange={() => {
											this.setState({
												isRangePicker: !this.state.isRangePicker
											});
										}}
									>
										{configs.map(config => (
											<TabPane tab={config.title} key={config.id} />
										))}
									</Tabs>
									<ReactDatesStyleWrapper className="isoReactDateConfig">
										{this.toggleOptions()}
									</ReactDatesStyleWrapper>
									<ReactDatesWrapper>
										{this.renderDatePicker(configs[0])}
									</ReactDatesWrapper>
								</ContentHolder>
							</Box>
						</Col>
					</Row>
				</LayoutWrapper>
			</div>
		);
	}
}
export default connect(state => ({
	view: state.App.view
}))(ReactDates);
