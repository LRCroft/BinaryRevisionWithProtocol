plugins { java } dependencies { testImplementation('junit:junit:4.13.2') } tasks.named<Test>('test') { useJUnit() }
