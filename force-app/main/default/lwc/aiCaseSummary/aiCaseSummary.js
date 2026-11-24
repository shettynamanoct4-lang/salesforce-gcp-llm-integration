import { LightningElement, api, track } from 'lwc';
import getCaseSummary from '@salesforce/apex/LlmInsightService.getCaseSummary';

export default class AiCaseSummary extends LightningElement {
    @api recordId;
    @track bullets = [];
    isLoading = false;
    error;

    get hasBullets() {
        return this.bullets.length > 0;
    }

    async handleGenerate() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const result = await getCaseSummary({ caseId: this.recordId });
            this.bullets = result.map((text, index) => ({ id: index, text }));
        } catch (e) {
            this.error = e?.body?.message || 'Something went wrong.';
            this.bullets = [];
        } finally {
            this.isLoading = false;
        }
    }
}
