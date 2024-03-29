[CmdletBinding(SupportsShouldProcess = $true)]
Param(
	[Parameter(Mandatory = $false)]
	[ValidateRange(1, 24)]
	[int] $VideosPerDay = 4,

	[switch] $UseExistingData,

	[switch] $SkipDescription,

	[switch] $OnlyUpdateCache
)

$combinedCachePath = "$PSScriptRoot\combinedCache.json"

. '.\YouTube.ps1'

function Get-ShuffledIndices([int] $Count) {
		[int[]] $result = @()

		do {
			$cur = $null

			do {
				[int] $cur = Get-Random -Minimum 0 -Maximum ($Count)
			} while ($result.Contains($cur))

			$result += $cur
		} while ($result.Length -lt $Count)

		return $result
	}

function Get-Description {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
		$DateTime
	)

	if ($SkipDescription) {
		return ''
	}

	$descriptionBoilerplate = "Feel free to use this footage for your own purposes. I would simply ask that you include a credit back to me for it."

	$year = $datetime.Substring(0, 4)
	$month = $datetime.Substring(5, 2)
	$day = $datetime.Substring(8, 2)
	$hour = $datetime.Substring(11, 2)
	$minute = $datetime.Substring(14, 2)
	$second = $datetime.Substring(17, 2)

	$datetimeStr = "$year-$month-$day $($hour):$($minute):$second"

	return @"
$dateTimeStr

$descriptionBoilerPlate
"@.Trim()
}

function Get-ZeroedDate {
	[CmdletBinding()]
	Param([Nullable[DateTime]] $DateTime)

	if ($DateTime) {
		$d = $DateTime
	} else {
		$d = Get-Date
	}

	return $d.AddMinutes(-$d.Minute).AddSeconds(-$d.Second).AddMilliseconds(-$d.Millisecond)
}

if (!(Test-Path $combinedCachePath) -or $OnlyUpdateCache) {
	if (!$UseExistingData -or !$YouTubeSearchResults) {
		$YouTubeSearchResults = Get-VideosSearch

		Write-Verbose "Updated `$videos"
	}

	$YouTubeCombinedResults = [hashtable[]]@()
	$YouTubeSearchResults
		| ForEach-Object {
			$YouTubeCombinedResults += ($_ | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json -AsHashtable)
		}

	if (!$UseExistingData -or !$YouTubeVideoResults) {
		$YouTubeVideoResults = Get-Videos -VideoIds ($YouTubeSearchResults | Select-Object -ExpandProperty id | Select-Object -ExpandProperty videoId)
	}

	$YouTubeVideoResults
		| ForEach-Object {
			$curVid = $_
			$result = $YouTubeCombinedResults | Where-Object { $curVid.id -eq $_.id.videoId }

			$result.status = $curVid.status
			$result.fileDetails = $curVid.fileDetails
		}

	Set-Content $combinedCachePath (ConvertTo-Json -Depth 10 $YouTubeCombinedResults)
}

$YouTubeCombinedResults = Get-Content $combinedCachePath | ConvertFrom-Json -Depth 10 -AsHashtable

if ($OnlyUpdateCache) {
	return
}

# we can assume that the last published video is the first video returned that has a set description
$lastVideoWithDescription = $YouTubeCombinedResults
	| Where-Object { $_.snippet.description }
	| Select-Object -First 1

if (!$lastVideoWithDescription) {
	Write-Host "No videos to schedule"

	return
}

$lastPublishedAt = $lastVideoWithDescription.snippet.publishedAt
$lastScheduledPublish = Get-ZeroedDate $lastVideoWithDescription.status.publishAt

Write-Verbose "`$lastPublishedAt (uploaded) = $lastPublishedAt"
Write-Verbose "`$lastScheduledPublish = $lastScheduledPublish"

[hashtable[]] $privateVideosWithoutSchedule = $YouTubeCombinedResults
	| Where-Object { $null -eq $_.status.publishAt -and $_.snippet.publishedAt -gt $lastPublishedAt -and 'private' -eq $_.status.privacyStatus }
	| Sort-Object { $_.snippet.publishedAt }

Write-Verbose "Number of private videos without schedule: $($privateVideosWithoutSchedule.Length)"

if ($privateVideosWithoutSchedule.Length -eq 0) {
	Write-Host "No videos to schedule"

	return
}

$scheduleIntervalHours = 24 / $VideosPerDay
if ($scheduleIntervalHours % 1 -ne 0) {
	throw "Please provide a value for VideosPerDay that divides 24 evenly"
}

$metadata = @()

$randomlyOrderedIndices = Get-ShuffledIndices -Count $privateVideosWithoutSchedule.Length
foreach ($index in $randomlyOrderedIndices) {
	$video = $privateVideosWithoutSchedule[$index]

	Write-Verbose "`$video = $(ConvertTo-Json -Depth 10 -Compress $video)"

	$game, $title, $datetime = ($video.fileDetails.fileName -Replace ".mp4", "") -Split " - "	

	$lastScheduledPublish = $lastScheduledPublish.AddHours($scheduleIntervalHours)

	$curData = @{
		Id = $video.id.videoId
		Title = "$game - $title"
		Description = (Get-Description $datetime)
		PublishAt = $lastScheduledPublish.ToString("yyyy-MM-ddTHH:mm:ssZ")
	}

	Update-Video @curData

	$metadata += $curData
}
