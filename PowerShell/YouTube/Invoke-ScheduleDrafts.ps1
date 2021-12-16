[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[Parameter(Mandatory = $false)]
	[ValidateRange(1, 24)]
	[int] $VideosPerDay = 4,

	[switch] $UseExistingData
)

. '.\YouTube.ps1'

function Get-ZeroedDate {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
		[DateTime] $DateTime
	)

	return $DateTime.AddMinutes(-$DateTime.Minute).AddSeconds(-$DateTime.Second).AddMilliseconds(-$DateTime.Millisecond)
}

if (!$UseExistingData -or !$global:YouTubeSearchResults) {
	$global:YouTubeSearchResults = Get-VideosSearch

	Write-Verbose "Updated `$global:videos"
}

$global:YouTubeCombinedResults = @()
$global:YouTubeSearchResults
	| ForEach-Object {
		$global:YouTubeCombinedResults += ($_ | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json -AsHashtable)
	}

if (!$UseExistingData -or !$global:YouTubeVideoResults) {
	$global:YouTubeVideoResults = Get-Videos -VideoIds ($global:YouTubeSearchResults | Select-Object -ExpandProperty id | Select-Object -ExpandProperty videoId)
}

$global:YouTubeVideoResults
	| ForEach-Object {
		$curVid = $_
		$result = $global:YouTubeCombinedResults | Where-Object { $curVid.id -eq $_.id.videoId }
		$result.status = $curVid.status
		$result.fileDetails = $curVid.fileDetails
	}

# we can assume that the last published video is the first video returned that has a set description
$lastVideoWithDescription = $global:YouTubeCombinedResults
	| Where-Object { "" -ne $_.snippet.description }
	| Select-Object -First 1

$lastPublishedAt = $lastVideoWithDescription.snippet.publishedAt
$lastScheduledPublish = Get-ZeroedDate $lastVideoWithDescription.status.publishAt

Write-Verbose "`$lastPublishedAt = $lastPublishedAt"
Write-Verbose "`$lastScheduledPublish = $lastScheduledPublish"

$privateVideosWithoutSchedule = $global:YouTubeCombinedResults
	| Where-Object { $null -eq $_.status.publishAt -and $_.snippet.publishedAt -gt $lastPublishedAt -and 'private' -eq $_.status.privacyStatus }
	| Sort-Object { $_.snippet.publishedAt }

$descriptionBoilerplate = "Feel free to use this footage for your own purposes. I would simply ask that you include a credit back to me for it."

$scheduleIntervalHours = 24 / $VideosPerDay
if ($scheduleIntervalHours % 1 -ne 0) {
	throw "Please provide a value for VideosPerDay that divides 24 evenly"
}

$metadata = @()

for ($i = 0; $i -lt $privateVideosWithoutSchedule.Length; $i++) {
	$video = $privateVideosWithoutSchedule[$i]

	$game, $title, $datetime = ($video.fileDetails.fileName -Replace ".mp4", "") -Split " - "

	$year = $datetime.Substring(0, 4)
	$month = $datetime.Substring(5, 2)
	$day = $datetime.Substring(8, 2)
	$hour = $datetime.Substring(11, 2)
	$minute = $datetime.Substring(14, 2)
	$second = $datetime.Substring(17, 2)

	$datetimeStr = "$year-$month-$day $($hour):$($minute):$second"

	$description = @"
$datetimeStr

$descriptionBoilerplate
"@.Trim()

	$lastScheduledPublish = $lastScheduledPublish.AddHours($scheduleIntervalHours)

	$curData = @{
		Id = $video.id.videoId
		Title = "$game - $title"
		Description = $description
		PublishAt = $lastScheduledPublish.ToString("o")
	}

	Update-Video @curData

	$metadata += $curData
}
